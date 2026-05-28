import Foundation
import SwiftData

/// Tek bir kural değerlendirmesinin sonucu.
struct MonitoringEvaluation: Sendable {
    let ruleId: UUID
    let checkType: CheckType
    let value: Double
    let triggered: Bool
    /// Hazırlanmış bildirim metni (placeholder'lar çözülmüş). Sadece triggered ise dolu.
    let renderedMessage: String?
    /// Hata mesajı (komut çalışmadıysa). Bu durumda value 0, triggered false.
    let error: String?
    /// Bu kural interval gating yüzünden bu sefer atlandı.
    let skipped: Bool
}

/// Sunucu bazlı tüm aktif kuralları sırayla çalıştırır, snapshot kaydeder,
/// threshold kontrolü yapıp tetiklenen kuralları döndürür.
///
/// Bildirim göndermez (Faz 4'te NotificationService bu sonucu tüketecek).
@MainActor
struct MonitoringEngine {

    let ssh: SSHService
    let context: ModelContext

    init(ssh: SSHService, context: ModelContext) {
        self.ssh = ssh
        self.context = context
    }

    /// Verilen sunucunun aktif kurallarını çalıştır.
    /// - Parameter force: `true` ise her kural çalışır (interval gating bypass).
    ///   Manuel "Run Now" akışları force=true gönderir, background task false.
    func evaluate(server: Server, force: Bool = false) async -> [MonitoringEvaluation] {
        var results: [MonitoringEvaluation] = []

        let credentials = server.credentials
        let enabledRules = server.rules.filter { $0.isEnabled }
        let now = Date()

        for rule in enabledRules {
            let rawCommand = rule.checkType.sshCommand(parameter: rule.customCommand)
            let wrapped = "(\(rawCommand)); true"

            // Interval gating — komut çalıştırma, sadece logla.
            guard rule.shouldRun(at: now, force: force) else {
                context.insert(LogEntry(
                    server: server,
                    timestamp: now,
                    kind: .ruleSkipped,
                    checkType: rule.checkType,
                    ruleId: rule.id,
                    command: wrapped,
                    output: nil,
                    errorMessage: nil,
                    value: rule.lastValue,
                    triggered: false,
                    durationMs: nil
                ))
                results.append(MonitoringEvaluation(
                    ruleId: rule.id,
                    checkType: rule.checkType,
                    value: rule.lastValue ?? 0,
                    triggered: false,
                    renderedMessage: nil,
                    error: nil,
                    skipped: true
                ))
                continue
            }

            // Pipeline exit code'larından kaçınmak için subshell + true ile sarmala.
            // Çıktı korunur, exit her zaman 0.

            let startedAt = Date()
            do {
                let output = try await ssh.runCommand(wrapped, on: credentials)
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                let value = Self.parseDouble(from: output)

                // Snapshot kaydet
                let snapshot = MetricSnapshot(
                    server: server,
                    checkType: rule.checkType,
                    value: value
                )
                context.insert(snapshot)

                // Threshold kontrolü
                let triggered: Bool = {
                    switch rule.thresholdDirection {
                    case .above: return value > rule.threshold
                    case .below: return value < rule.threshold
                    }
                }()

                rule.lastValue = value
                rule.lastCheckedAt = now
                if triggered {
                    rule.lastTriggeredAt = now
                }

                let rendered = triggered ? Self.renderMessage(
                    rule.notificationMessage,
                    value: value,
                    unit: rule.checkType.unit,
                    isByteValued: rule.checkType.isByteValued
                ) : nil

                // Log entry
                context.insert(LogEntry(
                    server: server,
                    timestamp: now,
                    kind: .ruleEvaluation,
                    checkType: rule.checkType,
                    ruleId: rule.id,
                    command: wrapped,
                    output: output,
                    errorMessage: nil,
                    value: value,
                    triggered: triggered,
                    durationMs: elapsed
                ))

                results.append(MonitoringEvaluation(
                    ruleId: rule.id,
                    checkType: rule.checkType,
                    value: value,
                    triggered: triggered,
                    renderedMessage: rendered,
                    error: nil,
                    skipped: false
                ))

                server.lastError = nil
            } catch {
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                let msg = error.localizedDescription
                server.lastError = msg
                // Hatayı da lastCheckedAt olarak işaretle — sonsuz retry loop'a girmemek için.
                rule.lastCheckedAt = now

                context.insert(LogEntry(
                    server: server,
                    timestamp: now,
                    kind: .ruleEvaluation,
                    checkType: rule.checkType,
                    ruleId: rule.id,
                    command: wrapped,
                    output: nil,
                    errorMessage: msg,
                    value: nil,
                    triggered: false,
                    durationMs: elapsed
                ))

                results.append(MonitoringEvaluation(
                    ruleId: rule.id,
                    checkType: rule.checkType,
                    value: 0,
                    triggered: false,
                    renderedMessage: nil,
                    error: msg,
                    skipped: false
                ))
            }
        }

        server.lastCheckedAt = now
        try? context.save()

        // Saklama süresi geçmiş entry'leri her cycle'da temizle.
        LogPurger.purgeOld(context: context)

        // Home-screen widget'ı için snapshot'ı yenile (App Group üzerinden paylaşılır).
        Self.refreshWidgetSnapshot(context: context)

        return results
    }

    /// Tüm sunucuların güncel durumunu okur ve WidgetSnapshot olarak kaydeder.
    /// Widget extension bu snapshot'ı App Group UserDefaults üzerinden okur.
    /// Best-effort: hata yutar; widget bir cycle eski veri gösterir.
    static func refreshWidgetSnapshot(context: ModelContext) {
        let descriptor = FetchDescriptor<Server>(sortBy: [SortDescriptor(\.createdAt)])
        guard let servers = try? context.fetch(descriptor) else { return }
        let summaries = servers.map { server -> WidgetSnapshot.ServerSummary in
            let active = server.rules.filter { $0.isEnabled }
            let triggered = active.filter { rule in
                guard let v = rule.lastValue else { return false }
                switch rule.thresholdDirection {
                case .above: return v > rule.threshold
                case .below: return v < rule.threshold
                }
            }.count
            return WidgetSnapshot.ServerSummary(
                name: server.name,
                host: server.host,
                triggeredCount: triggered,
                okCount: max(0, active.count - triggered),
                lastCheckedAt: server.lastCheckedAt,
                lastError: server.lastError
            )
        }
        WidgetSnapshotStore.write(WidgetSnapshot(updatedAt: .now, servers: summaries))
    }

    // MARK: - Parsing

    /// Bir komut çıktısından Double üretir.
    /// - İlk satırı alır, başındaki/sonundaki boşluğu temizler
    /// - Virgüllü ondalıkları nokta yapar
    /// - Parse edilemezse 0 döner
    static func parseDouble(from raw: String) -> Double {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? raw
        let cleaned = firstLine
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    /// `{value}` ve `{unit}` placeholder'larını çözer.
    /// Byte tipte: value zaten "1.43 TB" gibi human-readable döner, unit boş bırakılır.
    static func renderMessage(_ template: String, value: Double, unit: String, isByteValued: Bool = false) -> String {
        let formattedValue: String
        let displayUnit: String
        if isByteValued {
            formattedValue = ByteDisplay.format(value)
            displayUnit = ""
        } else if value.truncatingRemainder(dividingBy: 1) == 0 {
            formattedValue = String(Int(value))
            displayUnit = unit
        } else {
            formattedValue = String(format: "%.1f", value)
            displayUnit = unit
        }
        return template
            .replacingOccurrences(of: "{value}", with: formattedValue)
            .replacingOccurrences(of: "{unit}", with: displayUnit)
    }
}
