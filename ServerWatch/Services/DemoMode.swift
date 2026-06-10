import Foundation
import SwiftData

/// Release-shippable "Try Demo Mode" — installs two pretend servers with
/// pre-populated rules and snapshots so a new user (or an App Store reviewer
/// who doesn't have a Linux server handy) can see every screen of the app
/// without doing the SSH handshake.
///
/// Demo servers are tagged by `keychainKeyId` prefix `"demo-"`. The
/// monitoring engine skips them so they never trigger a real SSH dial-out
/// (which would fail because no Keychain key is stored for them).
///
/// The user can swipe-to-delete demo servers at any time; that's all the
/// cleanup needed.
@MainActor
enum DemoMode {

    /// Distinguishes demo servers from real ones across the codebase.
    static let keychainKeyPrefix = "demo-"

    /// True when this server is part of the demo dataset.
    static func isDemo(_ server: Server) -> Bool {
        server.keychainKeyId.hasPrefix(keychainKeyPrefix)
    }

    /// Returns true if the store already has at least one demo server, so
    /// callers can hide the "Try Demo Mode" button after first activation.
    static func isInstalled(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Server>()
        guard let servers = try? context.fetch(descriptor) else { return false }
        return servers.contains(where: isDemo)
    }

    /// Inserts two demo servers (one healthy, one with an active alert),
    /// their rules, and recent snapshots. Idempotent — calling twice does
    /// nothing the second time.
    static func install(into context: ModelContext) {
        guard !isInstalled(in: context) else { return }

        let prod = Server(
            name: "Production",
            host: "demo.local",
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
            host: "demo.local",
            port: 22,
            username: "deploy",
            keychainKeyId: "demo-staging",
            lastCheckedAt: Date().addingTimeInterval(-180),
            createdAt: Date().addingTimeInterval(-86_400 * 5)
        )
        staging.hostKeyFingerprint = "SHA256:demo-staging-fingerprint"
        context.insert(staging)

        installRules(on: prod, context: context, samples: [
            (.memoryUsage,            80, .above, 41.2),
            (.cpuLoad,                80, .above, 18.5),
            (.diskUsageRoot,          85, .above, 62.0),
            (.activeConnections,     500, .above, 127),
            (.dockerRunningContainers, 0, .above, 6),
            (.bandwidthMonthly,       16_000_000_000_000, .above, 4_320_000_000_000)
        ])

        installRules(on: staging, context: context, samples: [
            (.memoryUsage,         80, .above, 62.0),
            (.cpuLoad,             80, .above, 92.3),
            (.diskUsageRoot,       85, .above, 71.0),
            (.failedLoginAttempts, 10, .above, 14)
        ])
        for rule in staging.rules where (rule.lastValue ?? 0) > rule.threshold {
            rule.lastTriggeredAt = Date().addingTimeInterval(-60)
        }

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
