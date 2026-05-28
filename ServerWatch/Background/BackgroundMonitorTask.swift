import Foundation
import BackgroundTasks
import SwiftData

/// Periodic background task that runs MonitoringEngine on every active server.
///
/// iOS schedules this task at its own discretion (~15-30 min typically once
/// the system learns the app's usage pattern). The task gets at most ~30s of
/// runtime; we schedule the next occurrence immediately, then iterate servers
/// in parallel and post notifications for any triggered rules.
///
/// Triggered identifier: `com.serverhealth.monitor`
enum BackgroundMonitorTask {

    static let identifier = "com.serverhealth.monitor"

    /// Schedule the next background refresh. Safe to call multiple times.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // iOS treats this as a minimum, not a guarantee.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common reasons: not enrolled (info.plist), background refresh
            // disabled by the user, or simulator without entitlement. Log but
            // don't crash.
            print("BackgroundMonitorTask: schedule failed — \(error)")
        }
    }

    /// The actual work. Called from `.backgroundTask` modifier in ServerWatchApp.
    /// Runs as a detached @MainActor task because SwiftData mainContext is
    /// MainActor-isolated.
    @MainActor
    static func run(container: ModelContainer) async {
        // Schedule the next run first — iOS gives us ~30s and we want to be
        // queued even if we time out.
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

        // Iterate servers sequentially — fan-out to all of them in parallel
        // would crowd the ~30s budget. For a small number of servers (<5)
        // this fits comfortably; if we ever support more, switch to async let.
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
