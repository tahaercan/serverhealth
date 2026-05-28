# ServerWatch – SSH Server Monitor iOS App

## Proje Özeti

Sunucu sahibi geliştiriciler için SSH tabanlı iOS monitoring uygulaması.
Sunucuya **hiçbir şey kurulmadan**, SSH key authentication ile bağlanır.
Seçilen metrikleri arka planda kontrol eder, eşik aşımlarında local bildirim gönderir.

---

## Test Sunucusu

```
Host:     204.168.194.254
User:     root
Port:     22
```

Geliştirme ve SSH komut testleri bu sunucu üzerinde yapılacak.

---

## Teknik Stack

| Alan | Seçim | Gerekçe |
|---|---|---|
| UI | SwiftUI | Modern, iOS 17+ |
| SSH | Citadel (SwiftNIO SSH) | Apple ekosistemi, pure Swift |
| Veri | SwiftData | Metrik geçmişi, native |
| Background | BGAppRefreshTask | iOS standart background job |
| Güvenlik | Keychain | SSH private key saklama |
| Minimum iOS | 17.0 | SwiftData, modern API'ler |
| Mimari | MVVM | Testable, clean |

### Citadel Kurulumu (Package.swift / SPM)
```
https://github.com/orlandos-nl/Citadel
```

---

## Uygulama Mimarisi

```
ServerWatch/
├── App/
│   ├── ServerWatchApp.swift        # BGTask kayıt, app entry
│   └── AppDelegate.swift
│
├── Models/                         # SwiftData modelleri
│   ├── Server.swift                # Sunucu bilgileri
│   ├── MonitoringRule.swift        # Kural (check + threshold)
│   └── MetricSnapshot.swift        # Geçmiş kayıt
│
├── Services/
│   ├── SSHService.swift            # SSH bağlantı ve komut çalıştırma
│   ├── KeychainService.swift       # Private key saklama/okuma
│   ├── MonitoringEngine.swift      # Komut → parse → threshold kontrolü
│   └── NotificationService.swift  # Local bildirim gönderme
│
├── Background/
│   └── BackgroundMonitorTask.swift # BGAppRefreshTask implementasyonu
│
├── ViewModels/
│   ├── ServerListViewModel.swift
│   ├── ServerDetailViewModel.swift
│   ├── AddServerViewModel.swift
│   └── RulesViewModel.swift
│
└── Views/
    ├── Dashboard/
    │   ├── ServerListView.swift
    │   └── ServerCardView.swift
    ├── ServerDetail/
    │   ├── ServerDetailView.swift
    │   ├── MetricGridView.swift
    │   └── MetricHistoryChart.swift
    ├── AddServer/
    │   ├── AddServerView.swift      # Host/user/şifre form
    │   └── KeySetupProgressView.swift
    ├── Rules/
    │   ├── RulesListView.swift
    │   ├── AddRuleView.swift
    │   └── RuleTemplatesView.swift
    └── Settings/
        └── SettingsView.swift
```

---

## SwiftData Modelleri

```swift
@Model
class Server {
    var id: UUID
    var name: String           // kullanıcının verdiği isim (ör. "Production")
    var host: String
    var port: Int              // default 22
    var username: String
    var keychainKeyId: String  // Keychain'deki private key referansı
    var isActive: Bool
    var lastCheckedAt: Date?
    var createdAt: Date
    var rules: [MonitoringRule]
    var snapshots: [MetricSnapshot]
}

@Model
class MonitoringRule {
    var id: UUID
    var server: Server
    var checkType: CheckType   // enum (rawValue: String)
    var customCommand: String? // checkType == .custom ise
    var threshold: Double      // yüzde veya sayı
    var thresholdDirection: ThresholdDirection // .above / .below
    var notificationMessage: String
    var isEnabled: Bool
    var lastValue: Double?
    var lastTriggeredAt: Date?
}

@Model
class MetricSnapshot {
    var id: UUID
    var server: Server
    var checkType: CheckType
    var value: Double
    var recordedAt: Date
}
```

---

## SSH Servis Implementasyonu

```swift
import Citadel
import NIOSSH

actor SSHService {

    // MARK: - İlk Kurulum (şifre ile key deploy)
    func setupSSHKey(host: String, port: Int, username: String, password: String) async throws -> String {
        // 1. Key pair üret
        let keyPair = try generateEd25519KeyPair()
        let publicKeyString = keyPair.publicKeyOpenSSHFormat()

        // 2. Şifre ile bağlan
        let client = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: .passwordBased(username: username, password: password),
            hostKeyValidator: .acceptAnything,
            reconnect: .never
        )

        // 3. authorized_keys'e ekle
        let command = """
            mkdir -p ~/.ssh && \
            chmod 700 ~/.ssh && \
            echo '\(publicKeyString)' >> ~/.ssh/authorized_keys && \
            chmod 600 ~/.ssh/authorized_keys
            """
        let output = try await client.executeCommand(command)
        try await client.close()

        // 4. Private key'i Keychain'e kaydet
        let keyId = UUID().uuidString
        try KeychainService.store(privateKey: keyPair.privateKeyData(), for: keyId)

        // 5. Şifre hiçbir yerde saklanmıyor
        return keyId
    }

    // MARK: - Komut Çalıştır (key auth)
    func runCommand(_ command: String, on server: Server) async throws -> String {
        let privateKey = try KeychainService.load(for: server.keychainKeyId)

        let client = try await SSHClient.connect(
            host: server.host,
            port: server.port,
            authenticationMethod: .privateKey(
                username: server.username,
                privateKey: privateKey
            ),
            hostKeyValidator: .acceptAnything,
            reconnect: .never
        )

        defer { Task { try? await client.close() } }

        let result = try await client.executeCommand(command)
        return String(buffer: result).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Bağlantı Testi
    func testConnection(server: Server) async throws -> Bool {
        let output = try await runCommand("echo ok", on: server)
        return output == "ok"
    }
}
```

---

## Keychain Servis

```swift
import Security

enum KeychainService {

    private static let service = "com.serverwatch.sshkeys"

    static func store(privateKey: Data, for keyId: String) throws {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      keyId,
            kSecValueData as String:        privateKey,
            // AfterFirstUnlock: background task çalışırken erişim için kritik
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    static func load(for keyId: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  keyId,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return data
    }

    static func delete(for keyId: String) {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  keyId
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

---

## Monitoring Komutları

```swift
enum CheckType: String, CaseIterable, Codable {

    // Sistem
    case memoryUsage
    case cpuLoad
    case loadAverage1m
    case loadAverage15m
    case uptime
    case zombieProcessCount

    // Disk
    case diskUsageRoot
    case diskUsageCustomPath
    case diskIORead
    case diskIOWrite

    // Ağ
    case activeConnections
    case portOpen             // threshold: port numarası, beklenen: açık/kapalı
    case failedLoginAttempts

    // Servisler
    case serviceStatus        // systemctl is-active <service>
    case processCount
    case topCPUProcess        // en çok CPU yiyen process'in %'i

    // Docker
    case dockerRunningContainers
    case dockerStoppedContainers

    // Güncellemeler
    case pendingSecurityUpdates
    case rebootRequired

    // Güvenlik
    case activeSSHSessions
    case sudoUsageCount

    // Özel
    case custom

    var sshCommand: String {
        switch self {
        case .memoryUsage:
            return "free -b | awk 'NR==2{printf \"%.1f\", $3/$2*100}'"
        case .cpuLoad:
            return "top -bn1 | grep 'Cpu(s)' | awk '{print $2+$4}'"
        case .loadAverage1m:
            return "awk '{print $1}' /proc/loadavg"
        case .loadAverage15m:
            return "awk '{print $3}' /proc/loadavg"
        case .uptime:
            return "awk '{print int($1/3600)}' /proc/uptime"
        case .zombieProcessCount:
            return "ps aux | awk '$8==\"Z\"' | wc -l"
        case .diskUsageRoot:
            return "df / | awk 'NR==2{print $5}' | tr -d '%'"
        case .activeConnections:
            return "ss -tn | grep -c ESTABLISHED || echo 0"
        case .failedLoginAttempts:
            return "grep 'Failed password' /var/log/auth.log 2>/dev/null | grep \"$(date '+%b %d')\" | wc -l"
        case .pendingSecurityUpdates:
            return "apt list --upgradable 2>/dev/null | grep -c security || echo 0"
        case .rebootRequired:
            return "[ -f /var/run/reboot-required ] && echo 1 || echo 0"
        case .dockerRunningContainers:
            return "docker ps -q 2>/dev/null | wc -l"
        case .dockerStoppedContainers:
            return "docker ps -a --filter status=exited -q 2>/dev/null | wc -l"
        case .activeSSHSessions:
            return "who | wc -l"
        case .processCount:
            return "ps aux | wc -l"
        case .custom:
            return "" // MonitoringRule.customCommand kullanılır
        default:
            return "echo 0"
        }
    }

    var displayName: String {
        switch self {
        case .memoryUsage:          return "RAM Kullanımı"
        case .cpuLoad:              return "CPU Yükü"
        case .loadAverage1m:        return "Load Average (1dk)"
        case .loadAverage15m:       return "Load Average (15dk)"
        case .diskUsageRoot:        return "Disk Kullanımı (/)"
        case .activeConnections:    return "Aktif Bağlantılar"
        case .failedLoginAttempts:  return "Başarısız Login (bugün)"
        case .pendingSecurityUpdates: return "Bekleyen Güvenlik Güncellemesi"
        case .rebootRequired:       return "Reboot Gerekiyor"
        case .dockerRunningContainers: return "Çalışan Docker Container"
        case .dockerStoppedContainers: return "Durmuş Docker Container"
        case .activeSSHSessions:    return "Aktif SSH Oturumu"
        case .custom:               return "Özel Komut"
        default:                    return rawValue
        }
    }

    var unit: String {
        switch self {
        case .memoryUsage, .cpuLoad, .diskUsageRoot: return "%"
        case .uptime:               return "saat"
        case .activeConnections,
             .processCount,
             .activeSSHSessions:   return "adet"
        default:                    return ""
        }
    }
}
```

---

## Background Task

```swift
import BackgroundTasks

// MARK: - Kayıt (ServerWatchApp.swift içinde)
// .backgroundTask modifier ile SwiftUI App'e ekle:
//
// .backgroundTask(.appRefresh("com.serverwatch.monitor")) {
//     await BackgroundMonitorTask.run()
// }

struct BackgroundMonitorTask {

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: "com.serverwatch.monitor")
        // iOS bu süreyi garanti etmez, minimum olarak kullanır (~15-30 dk arası çalışır)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        // Bir sonraki çalışmayı hemen planla
        schedule()

        let sshService = SSHService()
        let servers = fetchActiveServers() // SwiftData'dan

        for server in servers {
            guard !server.rules.filter({ $0.isEnabled }).isEmpty else { continue }

            for rule in server.rules where rule.isEnabled {
                do {
                    let command = rule.checkType == .custom
                        ? (rule.customCommand ?? "echo 0")
                        : rule.checkType.sshCommand

                    let rawOutput = try await sshService.runCommand(command, on: server)
                    let value = Double(rawOutput) ?? 0

                    // Geçmişe kaydet
                    saveSnapshot(server: server, rule: rule, value: value)

                    // Threshold kontrolü
                    let triggered: Bool
                    switch rule.thresholdDirection {
                    case .above: triggered = value > rule.threshold
                    case .below: triggered = value < rule.threshold
                    }

                    if triggered {
                        NotificationService.send(
                            title: "⚠️ \(server.name)",
                            body: rule.notificationMessage
                                .replacingOccurrences(of: "{value}", with: String(format: "%.1f", value))
                                .replacingOccurrences(of: "{unit}", with: rule.checkType.unit)
                        )
                        rule.lastTriggeredAt = Date()
                    }

                    rule.lastValue = value
                    server.lastCheckedAt = Date()

                } catch {
                    // SSH bağlantı hatası — sessizce geç, dashboard'da göster
                    print("[\(server.name)] \(rule.checkType.displayName) hatası: \(error)")
                }
            }
        }
    }
}
```

---

## Bildirim Servisi

```swift
import UserNotifications

enum NotificationService {

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // anında gönder
        )

        UNUserNotificationCenter.current().add(request)
    }
}
```

---

## Ekranlar ve Akış

### 1. Onboarding / Sunucu Ekle
```
AddServerView
├── Sunucu adı (ör. "Production VPS")
├── Host / IP
├── Port (default: 22)
├── Kullanıcı adı
├── Şifre (sadece ilk kurulum için)
├── [Bağlan ve Kur] butonu
│
└── KeySetupProgressView (sheet)
    ├── ✓ Bağlantı kuruldu
    ├── ✓ SSH anahtarı oluşturuldu
    ├── ✓ Sunucuya eklendi
    └── ✓ Şifre silindi — artık saklanmıyor
```

### 2. Dashboard
```
ServerListView
├── Sunucu kartları (ServerCardView)
│   ├── Sunucu adı + host
│   ├── Son kontrol zamanı
│   ├── Aktif kural sayısı
│   └── Son durum (OK / ⚠️ Uyarı)
└── + Sunucu ekle butonu
```

### 3. Sunucu Detay
```
ServerDetailView
├── Canlı metrikler grid (MetricGridView)
│   ├── CPU, RAM, Disk, Uptime, Load, Connections
│   └── [Yenile] butonu (manuel, anlık SSH)
│
├── MetricHistoryChart
│   └── Seçili metriğin 24 saatlik grafiği (SwiftCharts)
│
└── Monitoring Kuralları listesi
    └── [Kural Ekle] butonu
```

### 4. Kural Ekle
```
AddRuleView
├── Şablonlar (RuleTemplatesView)
│   ├── "RAM %90 üzerine çıkarsa"
│   ├── "Disk %80 üzerine çıkarsa"
│   ├── "Başarısız login 10 üzerine çıkarsa"
│   └── ...
│
├── Veya özelleştir:
│   ├── Ne izlenecek? (CheckType picker)
│   ├── Eşik değeri (Slider + sayı)
│   ├── Yön (üzerine / altına düşerse)
│   └── Bildirim metni ("{value} {unit}" placeholder destekli)
│
└── [Kaydet]
```

### 5. Aktivite Geçmişi (Şeffaflık için kritik)
```
ActivityLogView
├── Her background kontrol kaydedilir
├── Çalıştırılan SSH komutunu göster
├── Sonucu göster
└── Hataları göster
```

### 6. Ayarlar
```
SettingsView
├── Kontrol sıklığı (10 / 15 / 30 dakika)
│   Not: "iOS bu süreyi garanti etmez, yaklaşık değerdir"
├── Bildirim sesi
├── Açık kaynak (GitHub linki)
└── SSH anahtarları yönetimi
```

---

## Güven & Şeffaflık (UI Metinleri)

Onboarding ve ayarlarda şu mesajlar mutlaka yer almalı:

```
"Şifreniz yalnızca ilk kurulum için kullanılır ve
 hiçbir yerde saklanmaz. SSH anahtarınız yalnızca
 bu cihazın Keychain'inde tutulur."

"Bu uygulama Anthropic, Apple veya üçüncü bir
 sunucuya bağlanmaz. Tüm bağlantılar doğrudan
 sizin sunucunuza yapılır."

"Sunucunuzda çalıştırılan her komut Aktivite
 Geçmişi'nde görüntülenebilir."
```

---

## Info.plist Gereksinimleri

```xml
<!-- Background fetch için -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>

<!-- BGTask identifier -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.serverwatch.monitor</string>
</array>
```

---

## MVP Geliştirme Sırası

### Faz 1 – Temel SSH (hemen test edilebilir)
- [ ] Citadel SPM bağımlılığı ekle
- [ ] SSHService: şifre ile bağlan + komut çalıştır
- [ ] Test: `root@204.168.194.254` üzerinde temel komutları çalıştır
- [ ] KeychainService implementasyonu
- [ ] SSH key kurulum akışı (setupSSHKey)
- [ ] Key ile yeniden bağlanmayı doğrula

### Faz 2 – Veri Katmanı
- [ ] SwiftData modelleri (Server, MonitoringRule, MetricSnapshot)
- [ ] MonitoringEngine: komut → parse → değer
- [ ] Tüm CheckType komutlarını test sunucusunda dene

### Faz 3 – UI
- [ ] ServerListView + AddServerView
- [ ] ServerDetailView + canlı metrik grid
- [ ] AddRuleView + şablonlar
- [ ] ActivityLogView

### Faz 4 – Background & Bildirimler
- [ ] BGAppRefreshTask kurulumu
- [ ] NotificationService
- [ ] Threshold kontrolü ve bildirim tetikleme
- [ ] Simulator'da BGTask debug (Xcode > Debug > Simulate Background Fetch)

### Faz 5 – Cila
- [ ] SwiftCharts ile metrik grafiği
- [ ] iOS widget (WidgetKit) – Pro özellik
- [ ] Onboarding ekranları
- [ ] Şeffaflık metinleri ve aktivite log

---

## Önemli Notlar

**BGAppRefreshTask Kısıtları:**
- iOS bu task'ın ne zaman çalışacağına kendisi karar verir
- Kullanıcı uygulamayı düzenli açarsa iOS daha sık çalıştırır
- Low Power Mode'da çalışmayabilir
- Kullanıcıya UI'da açıkça belirt: "~15-30 dakikada bir kontrol edilir"

**SSH Timeout:**
- connectTimeout: 15 saniye (yavaş sunucular için)
- commandTimeout: 10 saniye
- Background task toplam süresi: ~30 saniye — birden fazla sunucu varsa paralel çalıştır (async let)

**Linux Dağıtım Uyumluluğu:**
- `free`, `df`, `ps`, `ss` komutları POSIX standart — her distro'da çalışır
- `systemctl` → systemd gerektirir (çoğu modern distro)
- `apt` → Debian/Ubuntu spesifik — diğerleri için graceful fallback yaz
- `docker` → yüklü değilse hata yerine "Yüklü değil" göster

**Hata Yönetimi:**
- SSH bağlantı hatası → sunucu kartında ⚠️ göster, sessiz geç
- Parse hatası → lastValue'yu güncelleme, eski değeri tut
- Ardışık 3 bağlantı hatası → "Sunucuya ulaşılamıyor" bildirimi gönder

---

## Geliştirici Setup — Güvenlik Hook'u

İlk clone'dan sonra **bir kez** çalıştırılır:

```sh
./scripts/install-git-hooks.sh
```

Bu, `.git/hooks/pre-commit` altına `scripts/check-no-secret-logging.sh`'i bağlar. Her `git commit` öncesi şu pattern'ler için Swift kaynaklarını tarar:

- `print(...password...)`, `print(...passValue...)`, `print(...privateKey...)`
- `print(...KeychainService.load...)`, `print(...rawRepresentation...)`
- Aynısı `NSLog`, `dump`, `debugPrint` için

Eşleşme bulursa commit iptal olur, dosya+satır numarası raporlanır. Acil durumda `git commit --no-verify` ile bypass edilebilir (ama PR review'da bunu açıklamak gerekir).

Manuel check için: `./scripts/check-no-secret-logging.sh`
