import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ServerWatchApp: App {

    init() {
        // BGProcessingTask is not exposed through SwiftUI's .backgroundTask
        // modifier (only .appRefresh and .urlSession are). Register the
        // longer task class the UIKit way; this must happen during launch,
        // before applicationDidFinishLaunching returns, which App.init
        // satisfies.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundMonitorTask.processingIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await BackgroundMonitorTask.run(container: Self.modelContainer)
                task.setTaskCompleted(success: true)
            }
        }
    }

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

    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseManager)
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
                    // Load the Pro subscription product + check current
                    // entitlement so the gating and paywall have data ready
                    // by the time the user might hit them.
                    await purchaseManager.loadProduct()
                }
        }
        .modelContainer(Self.modelContainer)
        // BGAppRefreshTask handler — short (~30s), used during day-cadence
        // wake-ups. SwiftUI's .backgroundTask modifier auto-registers this.
        .backgroundTask(.appRefresh(BackgroundMonitorTask.identifier)) {
            await BackgroundMonitorTask.run(container: Self.modelContainer)
        }
    }
}
