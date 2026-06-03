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
                .init(name: "Production",
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
                // Lock the widget to dark so it matches the app's brand
                // language regardless of the user's system theme. WidgetKit
                // doesn't honor .preferredColorScheme; the container
                // background is the supported way to set a fixed surface.
                .containerBackground(for: .widget) {
                    ZStack {
                        Color.widgetBase
                        LinearGradient(
                            colors: [
                                Color.widgetGreen.opacity(0.10),
                                Color.widgetTeal.opacity(0.06),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    }
                }
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
            HStack(spacing: 8) {
                statusDot(for: focus)
                Text(focus.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // Host/IP intentionally NOT shown — the widget renders on the
            // lock screen and at-a-glance to anyone holding the phone, so
            // server addresses stay inside the app.

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
                    .foregroundStyle(Color.widgetGreen)
                    .lineLimit(1)
            } else {
                Text("No checks yet")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let last = focus.lastCheckedAt {
                Text(last, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
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
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(LinearGradient.widgetBrand)
                    .textCase(.uppercase)
                Spacer()
                Text(snap.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Show up to 3 servers (medium widget is short)
            // Host/IP intentionally omitted — addresses stay inside the app.
            ForEach(Array(snap.servers.prefix(3))) { srv in
                HStack(spacing: 10) {
                    statusDot(for: srv)
                    Text(srv.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let last = srv.lastCheckedAt {
                        Text(last, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer()
                    statusBadge(for: srv)
                }
            }

            if snap.servers.count > 3 {
                Text("+\(snap.servers.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
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
                .foregroundStyle(LinearGradient.widgetBrand)
            Text("No servers yet")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
            Text("Add a server in the app to see it here.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
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
                .foregroundStyle(Color.widgetGreen)
        }
    }

    private func statusColor(for srv: WidgetSnapshot.ServerSummary) -> Color {
        if srv.hasAlert { return .red }
        if srv.lastError != nil { return .orange }
        if srv.isHealthy { return Color.widgetGreen }
        return Color.white.opacity(0.3)
    }
}

// MARK: - Widget palette (duplicated from main app's Theme.swift because
// the widget extension can't import from the app target).

private extension Color {
    /// #0B0F12 — near-black base, matches the app icon and paywall.
    static let widgetBase  = Color(red: 0.043, green: 0.059, blue: 0.071)
    /// #3FD68A — primary brand accent for healthy states.
    static let widgetGreen = Color(red: 0.247, green: 0.839, blue: 0.541)
    /// #3FD6C6 — secondary brand accent for gradient companion.
    static let widgetTeal  = Color(red: 0.247, green: 0.839, blue: 0.776)
}

private extension LinearGradient {
    /// Standard brand gradient. Reused for the medium widget header and
    /// the empty-state icon so the widget reads like the app's paywall.
    static let widgetBrand = LinearGradient(
        colors: [Color.widgetGreen, Color.widgetTeal],
        startPoint: .leading,
        endPoint: .trailing
    )
}

#Preview(as: .systemSmall) {
    ServerStatusWidget()
} timeline: {
    ServerStatusEntry(date: .now, snapshot: WidgetSnapshot(
        updatedAt: .now,
        servers: [
            .init(name: "Production",
                  triggeredCount: 0, okCount: 5,
                  lastCheckedAt: .now, lastError: nil),
        ]
    ))
    ServerStatusEntry(date: .now, snapshot: WidgetSnapshot(
        updatedAt: .now,
        servers: [
            .init(name: "Staging",
                  triggeredCount: 2, okCount: 3,
                  lastCheckedAt: .now, lastError: nil),
        ]
    ))
}
