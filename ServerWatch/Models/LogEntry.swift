import Foundation
import SwiftData

/// Bir log girişinin türü.
enum LogKind: String, Codable, CaseIterable {
    /// Engine bir kuralı SSH üzerinden çalıştırıp sonuç aldı (başarı veya hata).
    case ruleEvaluation
    /// Engine bu turda kuralı interval gating ile atladı, komut çalıştırılmadı.
    case ruleSkipped
    /// AddServerView'da SSH key kurulumu yapıldı.
    case keySetup
    /// PackageInstaller kullanıcı onayıyla sunucuya paket kurdu (vnstat, jq vs).
    case packageInstall
    /// (İleride) Manuel ad-hoc komut çalıştırma.
    case manual

    var displayName: String {
        switch self {
        case .ruleEvaluation:  return String(localized: "Rule Evaluated")
        case .ruleSkipped:     return String(localized: "Rule Skipped")
        case .keySetup:        return String(localized: "Key Setup")
        case .packageInstall:  return String(localized: "Package Install")
        case .manual:          return String(localized: "Manual Command")
        }
    }
}

/// SSH üzerinden çalıştırılan her komutun veya engine kararının kalıcı kaydı.
/// LogPurger 3 günden eski entry'leri otomatik temizler.
@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID

    /// Hangi sunucuya ait — sunucu silinirse cascade ile bu loglar da silinir.
    var server: Server?

    var timestamp: Date

    /// LogKind.rawValue
    var kindRaw: String

    /// CheckType.rawValue (rule-bazlı log değilse nil — örn. keySetup)
    var checkTypeRaw: String?

    /// Hangi MonitoringRule tetikledi (silinen kural için stale olabilir)
    var ruleId: UUID?

    /// Çalıştırılan ham SSH komutu (engine wrapping dahil)
    var command: String

    /// Komut çıktısı. 4 KB ile sınırlanır (UI taşmasın diye).
    var output: String?

    /// Hata mesajı (varsa). Bu durumda output nil olur.
    var errorMessage: String?

    /// Parse edilmiş Double değer (varsa).
    var value: Double?

    /// Bu evaluation tetiklendi mi (rule yalnızca).
    var triggered: Bool

    /// Komut süresi (ms). Skipped/keySetup durumlarında nil olabilir.
    var durationMs: Int?

    // MARK: - Computed accessors

    var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }

    var checkType: CheckType? {
        get {
            guard let raw = checkTypeRaw else { return nil }
            return CheckType(rawValue: raw)
        }
        set { checkTypeRaw = newValue?.rawValue }
    }

    var hasError: Bool { errorMessage != nil }

    init(
        id: UUID = UUID(),
        server: Server?,
        timestamp: Date = .now,
        kind: LogKind,
        checkType: CheckType? = nil,
        ruleId: UUID? = nil,
        command: String,
        output: String? = nil,
        errorMessage: String? = nil,
        value: Double? = nil,
        triggered: Bool = false,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.server = server
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.checkTypeRaw = checkType?.rawValue
        self.ruleId = ruleId
        self.command = command
        // Output'u 4 KB'a kırp — bazı komutlar (cat /var/log/...) çok uzun olabilir.
        if let out = output, out.count > 4096 {
            self.output = String(out.prefix(4096)) + "\n…(kırpıldı)"
        } else {
            self.output = output
        }
        self.errorMessage = errorMessage
        self.value = value
        self.triggered = triggered
        self.durationMs = durationMs
    }
}
