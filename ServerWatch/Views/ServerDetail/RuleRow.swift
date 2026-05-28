import SwiftUI

struct RuleRow: View {
    @Bindable var rule: MonitoringRule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(rule.checkType.displayName)
                    .font(.subheadline.weight(.medium))

                if let param = rule.customCommand,
                   !param.isEmpty,
                   rule.checkType.needsParameter,
                   rule.checkType != .custom {
                    Text("(\(param))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusIcon
            }

            HStack(spacing: 8) {
                Text(thresholdLabel)
                Text("·")
                Text("~\(rule.intervalMinutes) min")
                if let last = rule.lastValue {
                    Text("·")
                    Text("Last: \(format(last))\(rule.checkType.unit.isEmpty ? "" : " " + rule.checkType.unit)")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .leading) {
            Button {
                rule.isEnabled.toggle()
            } label: {
                Label(rule.isEnabled ? "Pause" : "Resume",
                      systemImage: rule.isEnabled ? "pause.fill" : "play.fill")
            }
            .tint(rule.isEnabled ? .orange : .green)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if !rule.isEnabled {
            Image(systemName: "pause.circle.fill").foregroundStyle(.secondary)
        } else if rule.lastTriggeredAt != nil {
            Image(systemName: "bell.badge.fill").foregroundStyle(.red)
        } else if rule.lastCheckedAt != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
        }
    }

    private var thresholdLabel: String {
        let arrow = rule.thresholdDirection == .above ? ">" : "<"
        // Byte tabanlı CheckType'lar için human-readable byte gösterimi.
        if rule.checkType.isByteValued {
            return "\(arrow) \(ByteDisplay.format(rule.threshold))"
        }
        let value = format(rule.threshold)
        let unit  = rule.checkType.unit.isEmpty ? "" : " " + rule.checkType.unit
        return "\(arrow) \(value)\(unit)"
    }

    private func format(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }
}
