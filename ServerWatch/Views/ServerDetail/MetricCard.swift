import SwiftUI

struct MetricCard: View {
    let snapshot: MetricSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.checkType.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formattedValue)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
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
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
