import Foundation

/// SI-binary byte unit helpers — used for bandwidth thresholds.
///
/// We use base-1000 (SI / decimal — what ISPs and hosting providers quote in
/// their TB caps) rather than base-1024 (IEC). A "20 TB" Hetzner cap means
/// 20 * 10^12 bytes.
enum ByteUnit: String, CaseIterable, Identifiable {
    case mb = "MB"
    case gb = "GB"
    case tb = "TB"

    var id: String { rawValue }

    /// Bytes per unit.
    var multiplier: Double {
        switch self {
        case .mb: return 1_000_000
        case .gb: return 1_000_000_000
        case .tb: return 1_000_000_000_000
        }
    }

    /// User value (in this unit) → bytes for storage.
    func toBytes(_ value: Double) -> Double { value * multiplier }

    /// Bytes from storage → user-facing value in this unit.
    func fromBytes(_ bytes: Double) -> Double { bytes / multiplier }
}

/// Format bytes for display, picking a sensible unit automatically.
/// Uses Foundation's ByteCountFormatter with decimal (1000) base.
enum ByteDisplay {
    static func format(_ bytes: Double, allowedUnits: ByteCountFormatter.Units = [.useMB, .useGB, .useTB]) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = allowedUnits
        formatter.countStyle = .decimal // 1 KB = 1000 B, matches ISP billing
        formatter.includesUnit = true
        formatter.includesCount = true
        // ByteCountFormatter expects Int64 — clamp for safety.
        let safe = max(0, min(bytes, Double(Int64.max)))
        return formatter.string(fromByteCount: Int64(safe))
    }
}
