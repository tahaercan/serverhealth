import Foundation

// MARK: - Widget-side mirror of the shared snapshot
//
// The widget extension is a separate target and can't import types from the
// app. We duplicate the codable struct here so JSON encode/decode stays
// compatible. Keep both copies in sync — change one, change the other.

struct WidgetSnapshot: Codable, Equatable {
    static let appGroupID = "group.com.serverhealth.app"
    static let storageKey  = "widget.snapshot.v1"

    let updatedAt: Date
    let servers: [ServerSummary]

    struct ServerSummary: Codable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        let host: String
        let triggeredCount: Int
        let okCount: Int
        let lastCheckedAt: Date?
        let lastError: String?

        var hasAlert: Bool { triggeredCount > 0 }
        var isHealthy: Bool {
            triggeredCount == 0 && lastError == nil && lastCheckedAt != nil
        }
    }
}

/// Reads the snapshot from the shared App Group container. Returns nil if
/// nothing has been written yet (e.g. before the user installs a server).
enum WidgetSnapshotReader {
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
              let data = defaults.data(forKey: WidgetSnapshot.storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
