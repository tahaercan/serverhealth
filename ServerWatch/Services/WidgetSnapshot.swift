import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Snapshot of all servers' current health, shared between the main app and
/// the WidgetKit extension via an App Group UserDefaults suite.
///
/// The app writes this after every MonitoringEngine evaluation (and on rule
/// add/delete). The widget reads it from its TimelineProvider on every reload.
struct WidgetSnapshot: Codable, Equatable {

    /// App Group identifier — must match both the app and widget entitlements.
    static let appGroupID = "group.com.serverhealth.app"

    /// UserDefaults key under which the encoded snapshot is stored.
    static let storageKey  = "widget.snapshot.v1"

    let updatedAt: Date
    let servers: [ServerSummary]

    struct ServerSummary: Codable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        let host: String
        /// Number of rules currently above their threshold (triggered) at last check.
        let triggeredCount: Int
        /// Number of rules currently OK at last check.
        let okCount: Int
        let lastCheckedAt: Date?
        /// Last connection/parse error, if any, on the most recent run.
        let lastError: String?

        /// True if any rule is triggered.
        var hasAlert: Bool { triggeredCount > 0 }
        /// True if all rules are OK and we got a clean last check.
        var isHealthy: Bool {
            triggeredCount == 0 && lastError == nil && lastCheckedAt != nil
        }
    }
}

/// Writes WidgetSnapshot to the App Group container and prompts WidgetKit to
/// refresh. Safe to call from any thread.
enum WidgetSnapshotStore {

    /// Persists the given snapshot, then asks WidgetKit to reload timelines
    /// so the user sees fresh data without waiting for the next 15-min cycle.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID) else {
            // App Group not configured yet (e.g. simulator misconfig) — silently
            // skip. The widget will just show its placeholder. Don't crash the
            // engine over this.
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WidgetSnapshot.storageKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Reads the latest snapshot, or nil if nothing has been written yet.
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
              let data = defaults.data(forKey: WidgetSnapshot.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
