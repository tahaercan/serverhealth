import Foundation
import SwiftData

/// 3 günden eski LogEntry kayıtlarını temizler.
/// App açılışında ve her MonitoringEngine cycle'ından sonra çağrılır.
@MainActor
enum LogPurger {

    /// Varsayılan saklama süresi: 3 gün.
    nonisolated static let defaultRetention: TimeInterval = 3 * 24 * 60 * 60

    /// `olderThan` saniyeden eski tüm LogEntry'leri sil.
    /// - Returns: silinen entry sayısı (debug için).
    @discardableResult
    static func purgeOld(
        context: ModelContext,
        olderThan retention: TimeInterval = defaultRetention
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-retention)
        let descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        do {
            let stale = try context.fetch(descriptor)
            for entry in stale {
                context.delete(entry)
            }
            if !stale.isEmpty {
                try context.save()
            }
            return stale.count
        } catch {
            print("LogPurger: fetch/delete hatası — \(error)")
            return 0
        }
    }
}
