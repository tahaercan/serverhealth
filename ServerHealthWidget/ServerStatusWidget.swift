import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ServerStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Provider

struct ServerStatusProvider: TimelineProvider {

    func placeholder(in context: Context) -> ServerStatusEntry {
        ServerStatusEntry(
            date: .now,
            snapshot: WidgetSnapshot(updatedAt: .now, servers: [
                .init(name: "Production", host: "prod.example.com",
                      triggeredCount: 0, okCount: 5,
                      lastCheckedAt: .now, lastError: nil)
            ])
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ServerStatusEntry) -> Void) {
        completion(ServerStatusEntry(date: .now, snapshot: WidgetSnapshotReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ServerStatusEntry>) -> Void) {
        // We refresh on demand from the app (`WidgetCenter.reloadAllTimelines()`
        // after each MonitoringEngine evaluation). The 15-min fallback handles
        // the case where the app didn't run.
        let entry = ServerStatusEntry(date: .now, snapshot: WidgetSnapshotReader.read())
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Widget definition

struct ServerStatusWidget: Widget {
    let kind: String = "ServerStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ServerStatusProvider()) { entry in
            ServerStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Server Health")
        .description("Glance at your servers — green if everything's OK, red when a rule is triggered.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget UI

struct ServerStatusWidgetView: View {
    let entry: ServerStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snap = entry.snapshot, !snap.servers.isEmpty {
            switch family {
            case .systemSmall:  smallView(snap)
            default:            mediumView(snap)
            }
        } else {
            emptyView
        }
    }

    // MARK: - Small (single server focus)

    @ViewBuilder
    private func smallView(_ snap: WidgetSnapshot) -> some View {
        // Show the highest-priority server: any alert first, else first server.
        let focus = snap.servers.first(where: { $0.hasAlert })
                 ?? snap.servers.first!
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                statusDot(for: focus)
                Text(focus.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(focus.host)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Status summary line. Separate singular/plural paths so the
            // string catalog can localize each form independently.
            if focus.hasAlert {
                Group {
                    if focus.triggeredCount == 1 {
                        Label("\(focus.triggeredCount) alert",
                              systemImage: "exclamationmark.triangle.fill")
                    } else {
                        Label("\(focus.triggeredCount) alerts",
                              systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .lineLimit(1)
            } else if focus.lastError != nil {
                Label("Unreachable", systemImage: "wifi.slash")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if focus.lastCheckedAt != nil {
                Label("\(focus.okCount) OK", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else {
                Text("No checks yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let last = focus.lastCheckedAt {
                Text(last, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Medium (multiple servers)

    @ViewBuilder
    private func mediumView(_ snap: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server Health")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(snap.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Show up to 3 servers (medium widget is short)
            ForEach(Array(snap.servers.prefix(3))) { srv in
                HStack(spacing: 8) {
                    statusDot(for: srv)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(srv.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(srv.host)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    statusBadge(for: srv)
                }
            }

            if snap.servers.count > 3 {
                Text("+\(snap.servers.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No servers yet")
                .font(.caption.weight(.medium))
            Text("Add a server in the app to see it here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status helpers

    @ViewBuilder
    private func statusDot(for srv: WidgetSnapshot.ServerSummary) -> some View {
        Circle()
            .fill(statusColor(for: srv))
            .frame(width: 10, height: 10)
    }

    @ViewBuilder
    private func statusBadge(for srv: WidgetSnapshot.ServerSummary) -> some View {
        if srv.hasAlert {
            Text("\(srv.triggeredCount)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
        } else if srv.lastError != nil {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
    }

    private func statusColor(for srv: WidgetSnapshot.ServerSummary) -> Color {
        if srv.hasAlert { return .red }
        if srv.lastError != nil { return .orange }
        if srv.isHealthy { return .green }
        return .gray
    }
}

#Preview(as: .systemSmall) {
    ServerStatusWidget()
} timeline: {
    ServerStatusEntry(date: .now, snapshot: WidgetSnapshot(
        updatedAt: .now,
        servers: [
            .init(name: "Production", host: "prod.example.com",
                  triggeredCount: 0, okCount: 5,
                  lastCheckedAt: .now, lastError: nil),
        ]
    ))
    ServerStatusEntry(date: .now, snapshot: WidgetSnapshot(
        updatedAt: .now,
        servers: [
            .init(name: "Staging", host: "stg.example.com",
                  triggeredCount: 2, okCount: 3,
                  lastCheckedAt: .now, lastError: nil),
        ]
    ))
}
