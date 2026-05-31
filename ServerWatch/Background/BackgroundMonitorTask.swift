import Foundation
import BackgroundTasks
import SwiftData

/// Periodic background runner for MonitoringEngine. Schedules **two** kinds
/// of background work in parallel so iOS has more opportunities to actually
/// fire us:
///
/// 1. **BGAppRefreshTask** (`com.serverhealth.monitor`) — short (~30s),
///    iOS tries to schedule on a learned-cadence basis (15min–hours).
/// 2. **BGProcessingTask** (`com.serverhealth.monitor.processing`) — longer
///    (minutes), iOS prefers to schedule overnight while the device is
///    charging and idle. Better fallback for "check while user sleeps".
///
/// We rescue diagnostics into `BackgroundDiagnostics` on every schedule and
/// every run so the Settings → Background section can show the user proof
/// (or lack of proof) that iOS is actually firing us.
///
/// Both task types do the same work — evaluate every active server's rules
/// and post notifications for triggered ones.
enum BackgroundMonitorTask {

    /// Short refresh task — registered in Info.plist.
    static let identifier = "com.serverhealth.monitor"

    /// Longer processing task — registered in Info.plist. Apple often runs
    /// these overnight while the device is plugged in.
    static let processingIdentifier = "com.serverhealth.monitor.processing"

    // MARK: - Scheduling

    /// Submit BOTH a refresh and a processing request. Safe to call multiple
    /// times — iOS coalesces duplicates by identifier.
    static func schedule() {
        scheduleAppRefresh()
        scheduleProcessing()
    }

    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        submit(request)
    }

    private static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // Don't require network — every SSH call needs it of course, but if
        // we set requiresNetworkConnectivity = true Apple gates this even
        // more aggressively. Connectivity is checked per-rule by the engine.
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        submit(request)
    }

    private static func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
            BackgroundDiagnostics.recordSchedule(success: true, errorMessage: nil)
        } catch {
            // Common reasons:
            //   - identifier missing from Info.plist BGTaskSchedulerPermittedIdentifiers
            //   - Background App Refresh disabled by user
            //   - simulator without the entitlement (real device only)
            // Log, don't crash; the next launch tries again.
            let msg = "[\(request.identifier)] \(error.localizedDescription)"
            print("BackgroundMonitorTask: schedule failed — \(msg)")
            BackgroundDiagnostics.recordSchedule(success: false, errorMessage: msg)
        }
    }

    // MARK: - Run

    /// The actual work. Called from `.backgroundTask` modifiers in
    /// ServerWatchApp for both BGAppRefresh and BGProcessing identifiers.
    /// Runs as a @MainActor task because SwiftData mainContext is
    /// MainActor-isolated.
    @MainActor
    static func run(container: ModelContainer) async {
        let startedAt = Date()
        defer {
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            BackgroundDiagnostics.recordRun(durationMs: elapsed)
        }

        // Schedule the next runs first — iOS gives us limited time and we
        // want to be queued even if we time out mid-evaluation.
        schedule()

        let context = container.mainContext
        let descriptor = FetchDescriptor<Server>(
            predicate: #Predicate { $0.isActive }
        )

        let servers: [Server]
        do {
            servers = try context.fetch(descriptor)
        } catch {
            print("BackgroundMonitorTask: fetch failed — \(error)")
            return
        }

        let engine = MonitoringEngine(ssh: SSHService.shared, context: context)

        // Iterate servers sequentially — fan-out to all in parallel would
        // crowd the BGAppRefresh ~30s budget. For BGProcessing we have more
        // headroom but keep the same shape for simplicity. For <5 servers
        // this fits comfortably; switch to `async let` if we ever grow.
        for server in servers {
            let results = await engine.evaluate(server: server, force: false)
            for r in results where r.triggered {
                let body = r.renderedMessage ?? String(localized: "Threshold crossed")
                NotificationService.send(
                    title: "⚠️ \(server.name)",
                    subtitle: r.checkType.displayName,
                    body: body
                )
            }
        }

        // Purge old logs once per cycle (engine already does this per server,
        // but call here as a safety net for servers without rules).
        LogPurger.purgeOld(context: context)
    }
}
