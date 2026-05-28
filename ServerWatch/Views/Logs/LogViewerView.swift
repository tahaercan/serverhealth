import SwiftUI
import SwiftData

/// Shows all log entries for a server.
/// Filters: CheckType + triggered only + errors only.
struct LogViewerView: View {

    let server: Server

    @Query private var logs: [LogEntry]

    @State private var selectedCheckType: CheckType? = nil
    @State private var onlyTriggered: Bool = false
    @State private var onlyErrors: Bool = false
    @State private var selectedLog: LogEntry?

    init(server: Server) {
        self.server = server
        let serverId = server.id
        _logs = Query(
            filter: #Predicate<LogEntry> { entry in
                entry.server?.id == serverId
            },
            sort: [SortDescriptor(\LogEntry.timestamp, order: .reverse)]
        )
    }

    var body: some View {
        List {
            Section {
                filterControls
            }

            Section {
                if filteredLogs.isEmpty {
                    Text("No logs match this filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredLogs) { entry in
                        Button {
                            selectedLog = entry
                        } label: {
                            LogRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("Logs")
                    Spacer()
                    Text("\(filteredLogs.count) / \(logs.count)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Entries older than 3 days are auto-deleted.")
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedLog) { entry in
            LogDetailSheet(entry: entry)
        }
    }

    // MARK: - Filter

    @ViewBuilder
    private var filterControls: some View {
        Picker("Type", selection: $selectedCheckType) {
            Text("All types").tag(CheckType?.none)
            ForEach(usedCheckTypes, id: \.self) { type in
                Text(type.displayName).tag(CheckType?.some(type))
            }
        }
        Toggle("Triggered only (🚨)", isOn: $onlyTriggered)
        Toggle("Errors only (❌)", isOn: $onlyErrors)
        if hasActiveFilter {
            Button(role: .destructive) {
                selectedCheckType = nil
                onlyTriggered = false
                onlyErrors = false
            } label: {
                Label("Clear filters", systemImage: "xmark.circle")
            }
        }
    }

    private var hasActiveFilter: Bool {
        selectedCheckType != nil || onlyTriggered || onlyErrors
    }

    private var usedCheckTypes: [CheckType] {
        let raws = Set(logs.compactMap { $0.checkTypeRaw })
        return CheckType.allCases.filter { raws.contains($0.rawValue) }
    }

    private var filteredLogs: [LogEntry] {
        logs.filter { entry in
            if let selected = selectedCheckType, entry.checkType != selected { return false }
            if onlyTriggered && !entry.triggered { return false }
            if onlyErrors && !entry.hasError { return false }
            return true
        }
    }
}

// MARK: - Row

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            icon
                .font(.title3)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if entry.kind == .ruleSkipped {
                        Text("skipped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                    if let v = entry.value {
                        Text("·")
                        Text(formattedValue(v))
                    }
                    if let ms = entry.durationMs, entry.kind == .ruleEvaluation {
                        Text("·")
                        Text("\(ms) ms")
                    }
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        if let ct = entry.checkType {
            return ct.displayName
        }
        return entry.kind.displayName
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .ruleEvaluation:
            if entry.hasError {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            } else if entry.triggered {
                Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .ruleSkipped:
            Image(systemName: "forward.circle.fill").foregroundStyle(.gray)
        case .keySetup:
            if entry.hasError {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            } else {
                Image(systemName: "key.fill").foregroundStyle(.blue)
            }
        case .packageInstall:
            if entry.hasError {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            } else {
                Image(systemName: "shippingbox.fill").foregroundStyle(.indigo)
            }
        case .manual:
            Image(systemName: "terminal.fill").foregroundStyle(.purple)
        }
    }

    private func formattedValue(_ v: Double) -> String {
        let unit = entry.checkType?.unit ?? ""
        let suffix = unit.isEmpty ? "" : " " + unit
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(v))\(suffix)"
        }
        return String(format: "%.1f%@", v, suffix)
    }
}

// MARK: - Detail sheet

private struct LogDetailSheet: View {
    let entry: LogEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    LabeledContent("Date") {
                        Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                            .font(.callout.monospaced())
                    }
                    LabeledContent("Kind", value: entry.kind.displayName)
                    if let ct = entry.checkType {
                        LabeledContent("Check", value: ct.displayName)
                    }
                    if let v = entry.value {
                        LabeledContent("Value") {
                            let unit = entry.checkType?.unit ?? ""
                            Text(v.truncatingRemainder(dividingBy: 1) == 0
                                 ? "\(Int(v)) \(unit)"
                                 : String(format: "%.2f %@", v, unit))
                                .font(.callout.monospaced())
                        }
                    }
                    if let ms = entry.durationMs {
                        LabeledContent("Duration", value: "\(ms) ms")
                    }
                    if entry.triggered {
                        Label("Triggered", systemImage: "bell.badge.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Command") {
                    Text(entry.command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if let output = entry.output, !output.isEmpty {
                    Section("Output") {
                        Text(output)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let err = entry.errorMessage {
                    Section("Error") {
                        Text(err)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Log Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
