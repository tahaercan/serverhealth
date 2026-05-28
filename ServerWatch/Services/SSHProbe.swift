import Foundation

/// Lightweight one-shot probes that ask a server "what are you?" / "do you have X?".
/// Used by AddRuleView before suggesting checks that need extra tools.
enum SSHProbe {

    /// Coarse package manager family — drives which install command we use.
    enum DistroFamily: String, Sendable {
        case apt        // Debian, Ubuntu, Mint, Pop, etc.
        case dnf        // Fedora, RHEL, Alma, Rocky, CentOS Stream
        case apk        // Alpine
        case pacman     // Arch, Manjaro
        case unknown
    }

    struct ServerCapabilities: Sendable {
        let distroId: String              // "ubuntu", "debian", "alpine", ...
        let distroPrettyName: String      // "Ubuntu 24.04.4 LTS"
        let family: DistroFamily
        let hasVnstat: Bool
        let hasJq: Bool
        /// The interface the default route exits through, e.g. "eth0".
        let primaryInterface: String
    }

    /// Single SSH round-trip probe — gathers everything we need at once.
    /// Designed to be safe on minimal systems: every step has a fallback.
    static func capabilities(of credentials: ServerCredentials) async throws -> ServerCapabilities {
        let script = """
        echo "---DISTRO_ID---"
        ( . /etc/os-release 2>/dev/null && echo "$ID" ) || echo unknown
        echo "---DISTRO_NAME---"
        ( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" ) || echo unknown
        echo "---VNSTAT---"
        command -v vnstat >/dev/null 2>&1 && echo yes || echo no
        echo "---JQ---"
        command -v jq >/dev/null 2>&1 && echo yes || echo no
        echo "---IFACE---"
        ip route get 1.1.1.1 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
        echo "---END---"
        """

        let output = try await SSHService.shared.runCommand(script, on: credentials)
        let parts = parseDelimited(output)

        let distroId   = parts["DISTRO_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
        let prettyName = parts["DISTRO_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? distroId
        let hasVnstat  = (parts["VNSTAT"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
        let hasJq      = (parts["JQ"]     ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
        let iface      = (parts["IFACE"]  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return ServerCapabilities(
            distroId: distroId,
            distroPrettyName: prettyName,
            family: family(for: distroId),
            hasVnstat: hasVnstat,
            hasJq: hasJq,
            primaryInterface: iface.isEmpty ? "eth0" : iface
        )
    }

    // MARK: - Helpers

    private static func family(for distroId: String) -> DistroFamily {
        switch distroId {
        case "ubuntu", "debian", "raspbian", "linuxmint", "pop", "elementary", "kali":
            return .apt
        case "fedora", "rhel", "centos", "almalinux", "rocky", "ol", "amzn":
            return .dnf
        case "alpine":
            return .apk
        case "arch", "manjaro", "endeavouros":
            return .pacman
        default:
            return .unknown
        }
    }

    private static func parseDelimited(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        var currentValue: [String] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("---") && s.hasSuffix("---") {
                if let key = currentKey {
                    result[key] = currentValue.joined(separator: "\n")
                }
                let stripped = s.dropFirst(3).dropLast(3)
                currentKey = stripped == "END" ? nil : String(stripped)
                currentValue = []
            } else if currentKey != nil {
                currentValue.append(s)
            }
        }
        if let key = currentKey {
            result[key] = currentValue.joined(separator: "\n")
        }
        return result
    }
}
