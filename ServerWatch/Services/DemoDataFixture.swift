#if DEBUG
import Foundation
import SwiftData

/// Pre-populates the SwiftData store with fake servers, rules, and recent
/// snapshots so the dashboard and detail screens look populated for App
/// Store screenshot capture.
///
/// Gated by a launch argument so it never fires in normal Debug builds.
/// To enable in the sim:
///     xcrun simctl launch booted com.serverhealth.app --SH_DEMO_MODE
/// Or run from Xcode with "SH_DEMO_MODE" in the scheme's launch arguments.
///
/// The fixture is idempotent on the marker key "demo.installed" stored in
/// UserDefaults so it doesn't keep inserting duplicates on subsequent
/// launches.
@MainActor
enum DemoDataFixture {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("SH_DEMO_MODE") })
    }

    /// Which screen to land on for screenshot capture. Read from a launch
    /// arg like `--SH_DEMO_SCREEN=paywall`. Recognized values:
    /// `dashboard` (default), `detail`, `paywall`, `addrule`, `settings`.
    static var initialScreen: String {
        for arg in ProcessInfo.processInfo.arguments {
            if let eq = arg.range(of: "SH_DEMO_SCREEN=") {
                return String(arg[eq.upperBound...])
            }
        }
        return "dashboard"
    }

    static func installIfNeeded(into context: ModelContext) {
        guard isEnabled else { return }
        let key = "demo.installed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        // Two servers: Production (healthy) and Staging (with alerts).
        let prod = Server(
            name: "Production",
            host: "10.0.0.42",
            port: 22,
            username: "deploy",
            keychainKeyId: "demo-prod",
            lastCheckedAt: Date().addingTimeInterval(-90),
            createdAt: Date().addingTimeInterval(-86_400 * 7)
        )
        prod.hostKeyFingerprint = "SHA256:demo-prod-fingerprint"
        context.insert(prod)

        let staging = Server(
            name: "Staging",
            host: "10.0.0.43",
            port: 22,
            username: "deploy",
            keychainKeyId: "demo-staging",
            lastCheckedAt: Date().addingTimeInterval(-180),
            createdAt: Date().addingTimeInterval(-86_400 * 5)
        )
        staging.hostKeyFingerprint = "SHA256:demo-staging-fingerprint"
        context.insert(staging)

        // Rules for prod — all healthy.
        installRules(on: prod, context: context, samples: [
            (.memoryUsage,        80, .above, 41.2),
            (.cpuLoad,            80, .above, 18.5),
            (.diskUsageRoot,      85, .above, 62.0),
            (.activeConnections,  500, .above, 127),
            (.dockerRunningContainers, 0, .above, 6),
            (.bandwidthMonthly,   16_000_000_000_000, .above, 4_320_000_000_000)  // 4.32 TB this month
        ])

        // Rules for staging — one triggered (CPU > 80%).
        installRules(on: staging, context: context, samples: [
            (.memoryUsage,    80, .above, 62.0),
            (.cpuLoad,        80, .above, 92.3),    // triggered
            (.diskUsageRoot,  85, .above, 71.0),
            (.failedLoginAttempts, 10, .above, 14)  // triggered
        ])
        // Mark the triggered rules
        for rule in staging.rules where (rule.lastValue ?? 0) > rule.threshold {
            rule.lastTriggeredAt = Date().addingTimeInterval(-60)
        }

        // Recent snapshots — one per rule, so the grid renders nicely.
        for srv in [prod, staging] {
            for rule in srv.rules {
                let snap = MetricSnapshot(
                    server: srv,
                    checkType: rule.checkType,
                    value: rule.lastValue ?? 0,
                    recordedAt: Date().addingTimeInterval(-30)
                )
                context.insert(snap)
            }
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)

        // Pre-populate Background diagnostics with healthy-looking
        // counters so the Settings screenshot doesn't show the
        // BGTaskScheduler-not-available-on-simulator error.
        UserDefaults.standard.removeObject(forKey: "bg.lastScheduleError")
        UserDefaults.standard.set(Date().addingTimeInterval(-120), forKey: "bg.lastRunAt")
        UserDefaults.standard.set(Date().addingTimeInterval(-30),  forKey: "bg.lastScheduledAt")
        UserDefaults.standard.set(127, forKey: "bg.runCount")
        UserDefaults.standard.set(840, forKey: "bg.lastRunDurationMs")
    }

    private static func installRules(
        on server: Server,
        context: ModelContext,
        samples: [(CheckType, Double, ThresholdDirection, Double)]
    ) {
        for (type, threshold, direction, value) in samples {
            let rule = MonitoringRule(
                server: server,
                checkType: type,
                threshold: threshold,
                thresholdDirection: direction,
                notificationMessage: "\(type.displayName): {value} {unit}"
            )
            rule.lastValue = value
            rule.lastCheckedAt = Date().addingTimeInterval(-60)
            context.insert(rule)
        }
    }
}
#endif
