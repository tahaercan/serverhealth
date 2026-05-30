import SwiftUI
import SwiftData

struct ServerDetailView: View {

    @Bindable var server: Server
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @State private var isRefreshing: Bool = false
    @State private var refreshResult: String?
    @State private var showAddRule: Bool = false
    @State private var editingRule: MonitoringRule?
    @State private var showPaywall: Bool = false

    /// Free tier allows 3 rules per server. The 4th attempt opens the paywall.
    private var canAddMoreRules: Bool {
        purchaseManager.isPro || server.rules.count < 3
    }

    private func addRuleTapped() {
        if canAddMoreRules {
            showAddRule = true
        } else {
            showPaywall = true
        }
    }
    @State private var historyCheckType: HistoryParam?

    /// Identifiable wrapper so `.sheet(item:)` can drive history presentation
    /// from a CheckType (which isn't Identifiable on its own).
    private struct HistoryParam: Identifiable {
        let checkType: CheckType
        var id: String { checkType.rawValue }
    }

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("Address") {
                    Text("\(server.username)@\(server.host):\(server.port)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let last = server.lastCheckedAt {
                    LabeledContent("Last check") {
                        Text(last, style: .relative).foregroundStyle(.secondary)
                    }
                }
                if let err = server.lastError, !err.isEmpty {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Live Metrics") {
                if latestSnapshots.isEmpty {
                    Text("No data yet. Tap ↻ at the top right to refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(latestSnapshots, id: \.id) { snap in
                            Button {
                                historyCheckType = HistoryParam(checkType: snap.checkType)
                            } label: {
                                MetricCard(snapshot: snap)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Rules (\(server.rules.count))") {
                if server.rules.isEmpty {
                    Text("No rules yet. Add one below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(server.rules.sorted(by: { $0.checkType.displayName < $1.checkType.displayName })) { rule in
                        Button { editingRule = rule } label: {
                            RuleRow(rule: rule)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteRules)
                }

                Button {
                    addRuleTapped()
                } label: {
                    Label("Add Rule", systemImage: "plus.circle")
                }
            }

            if let msg = refreshResult {
                Section("Last Refresh") {
                    Text(msg)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(server.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    LogViewerView(server: server)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Logs")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing || server.rules.allSatisfy { !$0.isEnabled })
                .accessibilityLabel("Refresh")
            }
        }
        .sheet(isPresented: $showAddRule) {
            AddRuleView(server: server)
        }
        .sheet(item: $editingRule) { rule in
            AddRuleView(server: server, rule: rule)
        }
        .sheet(item: $historyCheckType) { param in
            MetricHistoryView(server: server, checkType: param.checkType)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                priceText: purchaseManager.priceText,
                monthlyEquivalentText: purchaseManager.monthlyEquivalentText,
                isPurchasing: purchaseManager.isPurchasing,
                onPurchase: { await purchaseManager.purchase() },
                onRestore:  { await purchaseManager.restore() }
            )
        }
    }

    // MARK: - Helpers

    /// Latest snapshot per CheckType.
    private var latestSnapshots: [MetricSnapshot] {
        let sorted = server.snapshots.sorted { $0.recordedAt > $1.recordedAt }
        var seen = Set<String>()
        var result: [MetricSnapshot] = []
        for snap in sorted where !seen.contains(snap.checkTypeRaw) {
            seen.insert(snap.checkTypeRaw)
            result.append(snap)
        }
        return result
    }

    private func refresh() {
        isRefreshing = true
        refreshResult = nil
        Task { @MainActor in
            let engine = MonitoringEngine(ssh: SSHService.shared, context: context)
            let results = await engine.evaluate(server: server, force: true)
            // Send a local notification for any triggered rule. UNUserNotificationCenter
            // delivers these in-app as banners too, so the user always knows.
            for r in results where r.triggered {
                let body = r.renderedMessage ?? String(localized: "Threshold crossed")
                NotificationService.send(
                    title: "⚠️ \(server.name)",
                    subtitle: r.checkType.displayName,
                    body: body
                )
            }
            let triggered = results.filter { $0.triggered }.count
            let errors    = results.filter { $0.error != nil }.count
            let ok        = results.filter { $0.error == nil && !$0.triggered && !$0.skipped }.count
            refreshResult = "✅ \(ok)  ·  🚨 \(triggered)  ·  ❌ \(errors)  ·  total \(results.count)"
            isRefreshing = false
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        let sorted = server.rules.sorted(by: { $0.checkType.displayName < $1.checkType.displayName })
        for i in offsets {
            context.delete(sorted[i])
        }
        try? context.save()
    }
}
