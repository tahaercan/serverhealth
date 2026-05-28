import SwiftUI
import Charts

/// Trend chart for a single check type on a single server. Pulls from the
/// server's MetricSnapshot history (created by the MonitoringEngine on every
/// evaluation) and renders a Swift Charts line + area mark, plus min/avg/max/last.
struct MetricHistoryView: View {

    let server: Server
    let checkType: CheckType

    @Environment(\.dismiss) private var dismiss

    enum TimeRange: String, CaseIterable, Identifiable {
        case h1, h6, h24, d7
        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .h1:  return 3600
            case .h6:  return 6 * 3600
            case .h24: return 24 * 3600
            case .d7:  return 7 * 24 * 3600
            }
        }
        var displayName: String {
            switch self {
            case .h1:  return "1h"
            case .h6:  return "6h"
            case .h24: return "24h"
            case .d7:  return "7d"
            }
        }
    }

    @State private var range: TimeRange = .h24

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Time range", selection: $range) {
                    ForEach(TimeRange.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                let data = snapshots(in: range)
                if data.count < 2 {
                    ContentUnavailableView {
                        Label("Not enough data yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Refresh a few times or wait for the next background check.")
                    }
                    .padding(.top, 40)
                } else {
                    chart(for: data)
                        .frame(height: 240)
                        .padding(.horizontal)

                    statsRow(for: data)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle(checkType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(for data: [MetricSnapshot]) -> some View {
        Chart(data, id: \.id) { snap in
            LineMark(
                x: .value("Time", snap.recordedAt),
                y: .value("Value", snap.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))

            AreaMark(
                x: .value("Time", snap.recordedAt),
                y: .value("Value", snap.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.linearGradient(
                colors: [Color.accentColor.opacity(0.30),
                         Color.accentColor.opacity(0.00)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel {
                    if let val = v.as(Double.self) {
                        Text(formatY(val))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel(format: xAxisFormat)
            }
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .h1, .h6:  return .dateTime.hour().minute()
        case .h24:      return .dateTime.hour()
        case .d7:       return .dateTime.month(.abbreviated).day()
        }
    }

    // MARK: - Stats

    @ViewBuilder
    private func statsRow(for data: [MetricSnapshot]) -> some View {
        let values = data.map { $0.value }
        let mn = values.min() ?? 0
        let mx = values.max() ?? 0
        let avg = values.reduce(0, +) / Double(values.count)
        let last = values.last ?? 0
        HStack(spacing: 16) {
            statCell("Min", value: mn)
            statCell("Avg", value: avg)
            statCell("Max", value: mx)
            statCell("Last", value: last)
        }
    }

    @ViewBuilder
    private func statCell(_ label: LocalizedStringKey, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatY(value))
                .font(.callout.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    /// Snapshots for this checkType in the chosen window, sorted ascending.
    private func snapshots(in window: TimeRange) -> [MetricSnapshot] {
        let cutoff = Date().addingTimeInterval(-window.interval)
        return server.snapshots
            .filter { $0.checkType == checkType && $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    /// Format a value for axis labels and stats. Byte-valued → ByteCountFormatter;
    /// boolean → "1" / "0"; else number with optional unit suffix.
    private func formatY(_ v: Double) -> String {
        if checkType.isByteValued {
            return ByteDisplay.format(v)
        }
        if checkType.isBoolean {
            return v > 0.5 ? "1" : "0"
        }
        let n = v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
        let unit = checkType.unit
        if unit.isEmpty { return n }
        if unit == "%"  { return n + "%" }
        return "\(n) \(unit)"
    }
}
