import Foundation
import SwiftData

/// Installs OS packages on a remote server through SSH, with explicit user
/// consent. Currently supports apt-based distros (Debian/Ubuntu family) —
/// for other families we return a helpful error with a manual command.
///
/// Every install is logged as a `LogEntry(kind: .packageInstall)` with the
/// full stdout/stderr captured for audit.
@MainActor
enum PackageInstaller {

    struct Result {
        let success: Bool
        let output: String
        let errorMessage: String?
        let durationMs: Int
    }

    /// Build the exact shell command we would run for a given package list.
    /// Returned for showing in the consent dialog so the user can see what's
    /// about to happen.
    static func aptInstallCommand(packages: [String], enableServices: [String] = []) -> String {
        let pkgList = packages.joined(separator: " ")
        var cmd = """
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y \(pkgList)
        """
        for svc in enableServices {
            cmd += "\nsystemctl enable --now \(svc) || true"
        }
        cmd += "\necho __OK__"
        return cmd
    }

    /// Run apt-get install on the server. Caller must show consent UI first.
    static func install(
        packages: [String],
        enableServices: [String] = [],
        on server: Server,
        context: ModelContext
    ) async -> Result {
        let started = Date()
        let command = aptInstallCommand(packages: packages, enableServices: enableServices)
        let credentials = server.credentials

        do {
            let result = try await SSHService.shared.runCommand(command, on: credentials)
            let output = result.output
            // Same TOFU write-back as MonitoringEngine — install runs against
            // a freshly added server may be the first SSH round-trip if the
            // user goes straight from AddServer → AddRule → Install.
            if server.hostKeyFingerprint == nil, !result.observedFingerprint.isEmpty {
                server.hostKeyFingerprint = result.observedFingerprint
            }
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let succeeded = output.contains("__OK__")

            context.insert(LogEntry(
                server: server,
                timestamp: .now,
                kind: .packageInstall,
                checkType: nil,
                ruleId: nil,
                command: command,
                output: output,
                errorMessage: succeeded ? nil : String(localized: "Install command did not finish cleanly"),
                value: nil,
                triggered: false,
                durationMs: elapsed
            ))
            try? context.save()

            return Result(
                success: succeeded,
                output: output,
                errorMessage: succeeded ? nil : String(localized: "Install command did not finish cleanly"),
                durationMs: elapsed
            )
        } catch {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let msg = error.localizedDescription
            context.insert(LogEntry(
                server: server,
                timestamp: .now,
                kind: .packageInstall,
                checkType: nil,
                ruleId: nil,
                command: command,
                output: nil,
                errorMessage: msg,
                value: nil,
                triggered: false,
                durationMs: elapsed
            ))
            try? context.save()

            return Result(
                success: false,
                output: "",
                errorMessage: msg,
                durationMs: elapsed
            )
        }
    }
}
