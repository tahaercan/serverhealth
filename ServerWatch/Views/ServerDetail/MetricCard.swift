import SwiftUI

/// Live metric tile shown in the dashboard's grid. Each card carries:
///   - a brand-gradient icon matching the metric type
///   - the metric name in small caps
///   - the value in a prominent monospaced font (status-colored when
///     a rule for this metric is currently triggered)
///   - a thin relative-time footer
///
/// When the metric corresponds to a triggered rule the card border picks
/// up the critical color so the user spots it without having to read.
struct MetricCard: View {
    let snapshot: MetricSnapshot
    /// Set when at least one rule for this CheckType is currently above
    /// its threshold. Drives the alert glow + value color.
    var isTriggered: Bool = false

    private var level: StatusLevel { isTriggered ? .critical : .ok }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandGlyph(icon: iconName, size: 28)
                Text(snapshot.checkType.displayName)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if isTriggered {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formattedValue)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        isTriggered ? AnyShapeStyle(Color.red)
                                    : AnyShapeStyle(Brand.gradient)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unitText.isEmpty {
                    Text(unitText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(snapshot.recordedAt, style: .relative)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .brandCard(cornerRadius: 14, level: isTriggered ? .critical : nil)
    }

    // MARK: - Icon

    private var iconName: String {
        switch snapshot.checkType {
        case .memoryUsage:             return "memorychip"
        case .cpuLoad, .topCPUProcess: return "cpu"
        case .loadAverage1m, .loadAverage15m: return "gauge.medium"
        case .uptime:                  return "clock"
        case .zombieProcessCount, .processCount: return "list.dash"
        case .diskUsageRoot, .diskUsageCustomPath: return "internaldrive"
        case .activeConnections:       return "antenna.radiowaves.left.and.right"
        case .portOpen:                return "network"
        case .failedLoginAttempts, .sudoUsageCount: return "lock.shield"
        case .serviceStatus:           return "gearshape.2"
        case .dockerRunningContainers,
             .dockerStoppedContainers: return "shippingbox"
        case .pendingSecurityUpdates:  return "shield"
        case .rebootRequired:          return "arrow.clockwise.circle"
        case .activeSSHSessions:       return "terminal"
        case .bandwidthMonthly, .bandwidthDaily: return "chart.bar.xaxis"
        case .custom:                  return "ellipsis.curlybraces"
        }
    }

    // MARK: - Formatting

    /// Boolean tipte 0/1 yerine yerelleştirilmiş etiket; byte tipte ByteCountFormatter.
    private var formattedValue: String {
        switch snapshot.checkType {
        case .portOpen:
            return snapshot.value > 0 ? String(localized: "Open") : String(localized: "Closed")
        case .serviceStatus:
            return snapshot.value > 0 ? String(localized: "Active") : String(localized: "Inactive")
        case .rebootRequired:
            return snapshot.value > 0 ? String(localized: "Required") : String(localized: "Not required")
        default:
            if snapshot.checkType.isByteValued {
                return ByteDisplay.format(snapshot.value)
            }
            if snapshot.value.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(snapshot.value))
            }
            return String(format: "%.1f", snapshot.value)
        }
    }

    private var unitText: String {
        // Byte-tipte ByteCountFormatter zaten "1.43 TB" döner; ekstra unit eklemeyelim.
        if snapshot.checkType.isBoolean || snapshot.checkType.isByteValued { return "" }
        return snapshot.checkType.unit
    }
}
