import Foundation

/// Threshold comparison direction.
enum ThresholdDirection: String, Codable, CaseIterable {
    case above  // trigger when value rises above threshold
    case below  // trigger when value falls below threshold

    var displayName: String {
        switch self {
        case .above: return String(localized: "Rises above")
        case .below: return String(localized: "Falls below")
        }
    }
}

/// Sunucuda çalıştırılacak metrik komutu türü.
///
/// Parametrik tipler (`.serviceStatus`, `.portOpen`, `.diskUsageCustomPath`, `.custom`)
/// için parametre `MonitoringRule.customCommand` alanında tutulur:
///   - `.custom` → customCommand: tam komut
///   - `.serviceStatus` → customCommand: servis adı (örn. "nginx")
///   - `.portOpen` → customCommand: port numarası (örn. "443")
///   - `.diskUsageCustomPath` → customCommand: dizin yolu (örn. "/var")
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

    // Ağ
    case activeConnections
    case portOpen
    case failedLoginAttempts

    // Servisler
    case serviceStatus
    case processCount
    case topCPUProcess

    // Docker
    case dockerRunningContainers
    case dockerStoppedContainers

    // Güncellemeler
    case pendingSecurityUpdates
    case rebootRequired

    // Güvenlik
    case activeSSHSessions
    case sudoUsageCount

    // Bandwidth (periyodik — vnstat gerektirir)
    case bandwidthMonthly
    case bandwidthDaily

    // Özel
    case custom

    /// Parametrik mi (UI'da parameter alanı göster).
    var needsParameter: Bool {
        switch self {
        case .serviceStatus, .portOpen, .diskUsageCustomPath, .custom: return true
        default: return false
        }
    }

    /// Bu CheckType byte tabanlı değer mi döner (bandwidth gibi)?
    /// True ise threshold byte cinsinden saklanır, UI'da MB/GB/TB unit picker'ı çıkar.
    var isByteValued: Bool {
        switch self {
        case .bandwidthMonthly, .bandwidthDaily: return true
        default: return false
        }
    }

    /// CheckType'ın kendi doğal periyodu (UI'da "Monthly" chip vs.).
    /// nil = anlık (instantaneous) check.
    var nativePeriod: PeriodLabel? {
        switch self {
        case .bandwidthMonthly:  return .monthly
        case .bandwidthDaily:    return .daily
        default:                  return nil
        }
    }

    /// Sunucuda olması gereken paketler — yoksa AddRuleView install önerir.
    var requiredPackages: [String] {
        switch self {
        case .bandwidthMonthly, .bandwidthDaily: return ["vnstat", "jq"]
        default:                                  return []
        }
    }

    /// Bu CheckType bandwidthMonthly/Daily gibi vnstat'tan veri okur mu?
    var requiresVnstat: Bool {
        requiredPackages.contains("vnstat")
    }

    /// SSH üzerinden çalıştırılacak ham komut.
    /// MonitoringEngine her komutu `(cmd); true` ile sarmalar — bu yüzden
    /// pipeline'lar exit code'ları nedeniyle hata fırlatmaz. Komut sadece
    /// tek bir sayısal değer yazdırmalı.
    func sshCommand(parameter: String?) -> String {
        switch self {
        case .memoryUsage:
            return "free -b | awk 'NR==2{printf \"%.1f\", $3/$2*100}'"

        case .cpuLoad:
            // top'un %Cpu(s) satırından user + system. Idle'da 0 döner.
            return "LC_ALL=C top -bn1 | grep 'Cpu(s)' | awk '{print $2+$4}'"

        case .loadAverage1m:
            return "awk '{print $1}' /proc/loadavg"

        case .loadAverage15m:
            return "awk '{print $3}' /proc/loadavg"

        case .uptime:
            // Çalışma süresi (saat)
            return "awk '{print int($1/3600)}' /proc/uptime"

        case .zombieProcessCount:
            return "ps aux | awk '$8==\"Z\"' | wc -l"

        case .diskUsageRoot:
            return "df / | awk 'NR==2{print $5}' | tr -d '%'"

        case .diskUsageCustomPath:
            let path = shellEscape(parameter ?? "/")
            return "df \(path) | awk 'NR==2{print $5}' | tr -d '%'"

        case .activeConnections:
            // ESTABLISHED bağlantı sayısı. tail -n +2 başlığı atlar.
            return "ss -tn state established | tail -n +2 | wc -l"

        case .portOpen:
            // 1 = açık, 0 = kapalı
            let port = parameter ?? "0"
            let escaped = shellEscape(port)
            return "ss -tln | awk '{print $4}' | grep -E ':\(escaped)$' >/dev/null && echo 1 || echo 0"

        case .failedLoginAttempts:
            // Bugünkü "Failed password" satır sayısı; auth.log yoksa 0
            return "grep 'Failed password' /var/log/auth.log 2>/dev/null | grep \"$(date '+%b %d')\" | wc -l"

        case .serviceStatus:
            // 1 = active, 0 = diğer
            let svc = shellEscape(parameter ?? "")
            return "[ \"$(systemctl is-active \(svc) 2>/dev/null)\" = active ] && echo 1 || echo 0"

        case .processCount:
            return "ps aux | wc -l"

        case .topCPUProcess:
            // En çok CPU yiyen process'in %'i
            return "ps aux --sort=-%cpu | awk 'NR==2{print $3}'"

        case .dockerRunningContainers:
            return "docker ps -q 2>/dev/null | wc -l"

        case .dockerStoppedContainers:
            return "docker ps -a --filter status=exited -q 2>/dev/null | wc -l"

        case .pendingSecurityUpdates:
            return "apt list --upgradable 2>/dev/null | grep -c security"

        case .rebootRequired:
            return "[ -f /var/run/reboot-required ] && echo 1 || echo 0"

        case .activeSSHSessions:
            return "who | wc -l"

        case .sudoUsageCount:
            // Bugünkü sudo invocation sayısı (journalctl tabanlı)
            return "journalctl _COMM=sudo --since today 2>/dev/null | wc -l"

        case .bandwidthMonthly:
            // vnstat -i <interface> --json m → rx + tx (byte, içinde bulunulan ay)
            // Interface: default route'un çıktığı (parameter ile override edilebilir, yoksa auto).
            // jq -r ile sayı döner (newline yok). Engine 0/1 exit code'una göre Double parse eder.
            return vnstatCommand(period: "m", parameter: parameter)

        case .bandwidthDaily:
            return vnstatCommand(period: "d", parameter: parameter)

        case .custom:
            return parameter ?? "echo 0"
        }
    }

    /// vnstat sorgu komutu üretici. `period` "m" (month) veya "d" (day).
    /// Parameter varsa interface override eder, yoksa default route'un çıktığı interface kullanılır.
    private func vnstatCommand(period: String, parameter: String?) -> String {
        let ifaceExpr: String
        if let p = parameter, !p.trimmingCharacters(in: .whitespaces).isEmpty {
            ifaceExpr = "'\(p.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
        } else {
            ifaceExpr = "\"$(ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}')\""
        }
        // -1 (--limit 1) günlük/aylık tek satır; .traffic.day[-1] / .month[-1] son periyot.
        // .rx + .tx toplam transfer. ByteCount olarak parse.
        // Null-safe: vnstat yeni kurulmuşsa month/day array'i boş olur ve [-1] null döner.
        // `// {rx:0,tx:0}` defaultu uyguluyoruz, sonra rx ve tx için de teker teker `// 0`.
        let key = period == "m" ? "month" : "day"
        return """
        IFACE=\(ifaceExpr); \
        vnstat --json \(period) -i "$IFACE" 2>/dev/null \
          | jq -r '.interfaces[0].traffic.\(key)[-1] // {rx:0,tx:0} | (.rx // 0) + (.tx // 0)'
        """
    }

    var displayName: String {
        switch self {
        case .bandwidthMonthly:        return String(localized: "Bandwidth (Monthly)")
        case .bandwidthDaily:          return String(localized: "Bandwidth (Daily)")
        case .memoryUsage:             return String(localized: "RAM Usage")
        case .cpuLoad:                 return String(localized: "CPU Load")
        case .loadAverage1m:           return String(localized: "Load Average (1m)")
        case .loadAverage15m:          return String(localized: "Load Average (15m)")
        case .uptime:                  return String(localized: "Uptime")
        case .zombieProcessCount:      return String(localized: "Zombie Processes")
        case .diskUsageRoot:           return String(localized: "Disk Usage (/)")
        case .diskUsageCustomPath:     return String(localized: "Disk Usage (custom path)")
        case .activeConnections:       return String(localized: "Active Connections")
        case .portOpen:                return String(localized: "Port Open")
        case .failedLoginAttempts:     return String(localized: "Failed Logins (today)")
        case .serviceStatus:           return String(localized: "Service Status")
        case .processCount:            return String(localized: "Process Count")
        case .topCPUProcess:           return String(localized: "Top CPU Process")
        case .dockerRunningContainers: return String(localized: "Docker Running")
        case .dockerStoppedContainers: return String(localized: "Docker Stopped")
        case .pendingSecurityUpdates:  return String(localized: "Pending Security Updates")
        case .rebootRequired:          return String(localized: "Reboot Required")
        case .activeSSHSessions:       return String(localized: "Active SSH Sessions")
        case .sudoUsageCount:          return String(localized: "Sudo Usage (today)")
        case .custom:                  return String(localized: "Custom Command")
        }
    }

    var unit: String {
        switch self {
        case .memoryUsage, .cpuLoad, .diskUsageRoot, .diskUsageCustomPath, .topCPUProcess:
            return "%"
        case .uptime:
            return String(localized: "hours")
        case .activeConnections, .processCount, .activeSSHSessions,
             .zombieProcessCount, .failedLoginAttempts, .sudoUsageCount,
             .dockerRunningContainers, .dockerStoppedContainers,
             .pendingSecurityUpdates:
            return String(localized: "count")
        case .loadAverage1m, .loadAverage15m:
            return ""
        case .portOpen, .rebootRequired, .serviceStatus:
            return ""  // 0/1 boolean
        case .bandwidthMonthly, .bandwidthDaily:
            return ""  // byte, ByteCountFormatter ile gösterilir
        case .custom:
            return ""
        }
    }

    /// PeriodLabel — UI'da chip olarak gösterilir.
    enum PeriodLabel: String, Codable {
        case monthly
        case daily
        case weekly
        var displayName: String {
            switch self {
            case .monthly: return String(localized: "Monthly")
            case .daily:   return String(localized: "Daily")
            case .weekly:  return String(localized: "Weekly")
            }
        }
    }

    /// Boolean (0/1) tipli check mi.
    var isBoolean: Bool {
        switch self {
        case .portOpen, .rebootRequired, .serviceStatus: return true
        default: return false
        }
    }

    // MARK: - Helpers

    /// Tek tırnak içine alarak güvenli hale getirir. Tek tırnak içeren parametreleri de doğru escape eder.
    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
