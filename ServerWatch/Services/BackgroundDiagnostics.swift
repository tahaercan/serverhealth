import Foundation

/// Persistent counters for the background monitor — written by
/// BackgroundMonitorTask, read by SettingsView's diagnostics row.
///
/// We store these in UserDefaults instead of LogEntry because they need to
/// survive log purging and need to be cheap to write/read on every BG fire.
/// Read with `current()`, mutate with the recordXxx() helpers.
enum BackgroundDiagnostics {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let lastScheduledAt   = "bg.lastScheduledAt"
        static let lastScheduleError = "bg.lastScheduleError"
        static let lastRunAt         = "bg.lastRunAt"
        static let runCount          = "bg.runCount"
        static let lastRunDurationMs = "bg.lastRunDurationMs"
    }

    struct Snapshot {
        let lastScheduledAt: Date?
        let lastScheduleError: String?
        let lastRunAt: Date?
        let runCount: Int
        let lastRunDurationMs: Int?
    }

    static func current() -> Snapshot {
        Snapshot(
            lastScheduledAt:   defaults.object(forKey: Key.lastScheduledAt)   as? Date,
            lastScheduleError: defaults.string(forKey: Key.lastScheduleError),
            lastRunAt:         defaults.object(forKey: Key.lastRunAt)         as? Date,
            runCount:          defaults.integer(forKey: Key.runCount),
            lastRunDurationMs: (defaults.object(forKey: Key.lastRunDurationMs) as? Int)
        )
    }

    /// Called by BackgroundMonitorTask.schedule() after each submit attempt.
    /// `error` is the human-readable string from the submit failure, or nil
    /// on success.
    static func recordSchedule(success: Bool, errorMessage: String?) {
        defaults.set(Date(), forKey: Key.lastScheduledAt)
        if success {
            defaults.removeObject(forKey: Key.lastScheduleError)
        } else if let message = errorMessage {
            defaults.set(message, forKey: Key.lastScheduleError)
        }
    }

    /// Called from BackgroundMonitorTask.run() — the proof that iOS actually
    /// fired our task. `durationMs` is wall-clock time the run took.
    static func recordRun(durationMs: Int) {
        defaults.set(Date(), forKey: Key.lastRunAt)
        defaults.set(defaults.integer(forKey: Key.runCount) + 1, forKey: Key.runCount)
        defaults.set(durationMs, forKey: Key.lastRunDurationMs)
    }
}
