import SwiftUI
import SwiftData

@main
struct ServerWatchApp: App {

    /// SwiftData container. Uses `ServerHealthMigrationPlan` so future schema
    /// changes can preserve existing user data via lightweight or custom
    /// migration stages (see ServerHealthSchema.swift).
    ///
    /// On a **DEBUG** build, if migration / schema load fails for any reason
    /// (typically because of a half-written store from a previous dev session)
    /// we wipe the store files and try again. This safety net is gated behind
    /// `#if DEBUG` so release builds surface the error instead of silently
    /// destroying user data.
    static let modelContainer: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try buildContainer(configuration: configuration)
        } catch {
            #if DEBUG
            print("ModelContainer: initial load failed (\(error)) — wiping store (DEBUG fallback)")
            wipeStoreFiles()
            do {
                return try buildContainer(configuration: configuration)
            } catch {
                fatalError("ModelContainer creation failed after wipe: \(error)")
            }
            #else
            // Release: surface the failure rather than destroy user data.
            fatalError("ModelContainer creation failed: \(error)")
            #endif
        }
    }()

    private static func buildContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Server.self,
                 MonitoringRule.self,
                 MetricSnapshot.self,
                 LogEntry.self,
            migrationPlan: ServerHealthMigrationPlan.self,
            configurations: configuration
        )
    }

    private static func wipeStoreFiles() {
        guard let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Install the foreground notification delegate so iOS shows
                    // banners even while the app is open.
                    NotificationService.install()
                    // Purge old log entries on app launch.
                    let purged = LogPurger.purgeOld(
                        context: Self.modelContainer.mainContext
                    )
                    if purged > 0 {
                        print("LogPurger: removed \(purged) stale entries")
                    }
                    // Schedule the periodic background monitor on every launch.
                    BackgroundMonitorTask.schedule()
                }
        }
        .modelContainer(Self.modelContainer)
        // Register the BGAppRefreshTask handler. iOS calls this when it
        // decides to wake the app for a refresh (~15-30 min typical cadence).
        .backgroundTask(.appRefresh(BackgroundMonitorTask.identifier)) {
            await BackgroundMonitorTask.run(container: Self.modelContainer)
        }
    }
}
