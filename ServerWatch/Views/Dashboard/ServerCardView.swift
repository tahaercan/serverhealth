import SwiftUI

struct ServerCardView: View {
    let server: Server

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(server.name)
                    .font(.headline)
                Spacer()
                statusIcon
            }

            Text("\(server.username)@\(server.host):\(server.port)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Label("\(server.rules.count) rules", systemImage: "list.bullet")
                if let last = server.lastCheckedAt {
                    Text("·")
                    Image(systemName: "clock")
                    Text(last, style: .relative)
                } else {
                    Text("·")
                    Text("Not checked yet")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let err = server.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if server.lastError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if server.rules.contains(where: { $0.lastTriggeredAt != nil }) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.red)
        } else if server.lastCheckedAt != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }
}
