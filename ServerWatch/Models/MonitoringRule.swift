import Foundation
import SwiftData

@Model
final class MonitoringRule {
    @Attribute(.unique) var id: UUID
    var server: Server?

    /// SwiftData rawValue olarak saklar.
    var checkTypeRaw: String
    /// Parametrik kontroller için (servis adı, port, yol) veya `.custom` için ham komut.
    var customCommand: String?

    /// Eşik değeri. Byte tabanlı CheckType'lar (`isByteValued`) için DAHİLİ olarak
    /// **byte cinsinden** saklanır. UI input/display sırasında `thresholdUnit`
    /// kullanılarak MB/GB/TB'ya çevrilir. Diğer tipler için anlam değişmedi
    /// (ör. % için 80, count için 500, vs).
    var threshold: Double

    /// Threshold'un kullanıcı tarafından girildiği birim (sadece byte tabanlı
    /// CheckType'lar için anlamlı). "" → CheckType'ın default unit'i (bandwidth
    /// için GB). Örnek değerler: "MB", "GB", "TB".
    /// Inline default ŞART — SwiftData lightweight migration için, eski kayıtlar
    /// bu alana sahip değildi.
    var thresholdUnit: String = ""

    var thresholdDirectionRaw: String

    /// Bu kuralın ne sıklıkla çalıştırılacağı (dakika).
    /// iOS BGAppRefreshTask garanti vermez — bu değer best-effort gating'tir.
    /// Engine her uyandığında: lastCheckedAt + intervalMinutes <= now ise çalışır.
    var intervalMinutes: Int = 15

    /// "{value} {unit}" placeholder'larını destekler.
    var notificationMessage: String
    var isEnabled: Bool

    var lastValue: Double?
    var lastCheckedAt: Date?
    var lastTriggeredAt: Date?

    /// Computed accessor — SwiftData rawValue üzerinden gider.
    var checkType: CheckType {
        get { CheckType(rawValue: checkTypeRaw) ?? .custom }
        set { checkTypeRaw = newValue.rawValue }
    }

    var thresholdDirection: ThresholdDirection {
        get { ThresholdDirection(rawValue: thresholdDirectionRaw) ?? .above }
        set { thresholdDirectionRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        server: Server,
        checkType: CheckType,
        customCommand: String? = nil,
        threshold: Double,
        thresholdUnit: String = "",
        thresholdDirection: ThresholdDirection,
        intervalMinutes: Int = 15,
        notificationMessage: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.server = server
        self.checkTypeRaw = checkType.rawValue
        self.customCommand = customCommand
        self.threshold = threshold
        self.thresholdUnit = thresholdUnit
        self.thresholdDirectionRaw = thresholdDirection.rawValue
        self.intervalMinutes = intervalMinutes
        self.notificationMessage = notificationMessage
        self.isEnabled = isEnabled
    }

    /// Engine bu kuralı şu an çalıştırmalı mı?
    /// - `force == true` ise daima evet (manuel tetiklemede gating bypass).
    /// - Aksi halde lastCheckedAt + intervalMinutes <= now ise evet.
    func shouldRun(at date: Date = .now, force: Bool = false) -> Bool {
        if force { return true }
        guard let last = lastCheckedAt else { return true }
        let nextEligible = last.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        return date >= nextEligible
    }
}
