import SwiftUI

/// Rich dashboard card for a single server. Designed to read at a glance:
///   - colored status indicator strip on the leading edge
///   - server name + status pill on the same row
///   - host/port in monospace
///   - rule count + last-check time as light footer chips
///   - red glow border + warning message when in alert state
struct ServerCardView: View {
    let server: Server

    private var level: StatusLevel {
        if server.lastError != nil { return .critical }
        if server.rules.contains(where: { $0.lastTriggeredAt != nil }) { return .critical }
        if server.lastCheckedAt != nil { return .ok }
        return .neutral
    }

    private var statusPillText: LocalizedStringKey {
        switch level {
        case .ok:       return "Healthy"
        case .critical:
            if server.lastError != nil { return "Unreachable" }
            return "Alert"
        case .neutral:  return "Idle"
        default:        return "—"
        }
    }

    private var statusPillIcon: String {
        switch level {
        case .ok:       return "checkmark.circle.fill"
        case .critical:
            if server.lastError != nil { return "wifi.slash" }
            return "exclamationmark.triangle.fill"
        case .neutral:  return "circle.dashed"
        default:        return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Status strip — vertical, brand-gradient when OK, status color
            // otherwise. Reads as a tiny indicator without dominating the row.
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    level == .ok
                        ? AnyShapeStyle(Brand.gradient)
                        : AnyShapeStyle(level.color)
                )
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(server.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusPill(icon: statusPillIcon, text: statusPillText, level: level)
                }

                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 10) {
                    Label("\(server.rules.count)", systemImage: "list.bullet")
                    if let last = server.lastCheckedAt {
                        Label(last.formatted(.relative(presentation: .numeric)),
                              systemImage: "clock")
                    } else {
                        Label("Not checked yet", systemImage: "clock.badge.questionmark")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

                if let err = server.lastError, !err.isEmpty {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 14)
            .padding(.trailing, 14)
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(cornerRadius: 16, level: level == .ok ? nil : level)
        .padding(.vertical, 4)
    }
}
