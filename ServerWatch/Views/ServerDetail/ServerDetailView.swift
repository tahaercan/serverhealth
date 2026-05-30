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
        ZStack {
            BrandBackground()
            List {
                heroSection
                metricsSection
                rulesSection
                if let msg = refreshResult {
                    Section {
                        Text(msg)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } header: {
                        sectionLabel("Last Refresh")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
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
                isProductAvailable: purchaseManager.isProductAvailable,
                errorMessage: purchaseManager.lastErrorMessage,
                onPurchase: { await purchaseManager.purchase() },
                onRestore:  { await purchaseManager.restore() }
            )
        }
    }

    // MARK: - Branded sections

    /// Hero card — server identity + status + last check. Replaces the
    /// plain "Server" section header so the screen opens with a confident,
    /// branded surface that matches the paywall language.
    @ViewBuilder
    private var heroSection: some View {
        Section {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    BrandGlyph(icon: "server.rack", size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(server.name)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                        Text("\(server.username)@\(server.host):\(server.port)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    heroStatusPill
                }

                Divider().background(.white.opacity(0.08))

                HStack(spacing: 24) {
                    heroStat(label: "Rules", value: "\(server.rules.count)",
                             icon: "list.bullet")
                    if let last = server.lastCheckedAt {
                        heroStat(
                            label: "Last check",
                            value: last.formatted(.relative(presentation: .numeric)),
                            icon: "clock"
                        )
                    } else {
                        heroStat(label: "Last check", value: String(localized: "Never"),
                                 icon: "clock.badge.questionmark")
                    }
                    Spacer(minLength: 0)
                }

                if let err = server.lastError, !err.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(err)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
                            )
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandHeroCard(cornerRadius: 20)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var heroStatusPill: some View {
        let triggeredCount = server.rules.filter { $0.lastTriggeredAt != nil }.count
        if server.lastError != nil {
            StatusPill(icon: "wifi.slash", text: "Unreachable", level: .critical)
        } else if triggeredCount > 0 {
            StatusPill(
                icon: "exclamationmark.triangle.fill",
                text: triggeredCount == 1 ? "1 alert" : "\(triggeredCount) alerts",
                level: .critical
            )
        } else if server.lastCheckedAt != nil {
            StatusPill(icon: "checkmark.circle.fill", text: "Healthy", level: .ok)
        } else {
            StatusPill(icon: "circle.dashed", text: "Idle", level: .neutral)
        }
    }

    @ViewBuilder
    private func heroStat(label: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        Section {
            if latestSnapshots.isEmpty {
                Text("No data yet. Tap ↻ at the top right to refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .brandCard(cornerRadius: 12)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(latestSnapshots, id: \.id) { snap in
                        Button {
                            historyCheckType = HistoryParam(checkType: snap.checkType)
                        } label: {
                            MetricCard(snapshot: snap, isTriggered: isTriggered(snap))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            sectionLabel("Live Metrics")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            if server.rules.isEmpty {
                Text("No rules yet. Add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .brandCard(cornerRadius: 12)
            } else {
                ForEach(server.rules.sorted(by: { $0.checkType.displayName < $1.checkType.displayName })) { rule in
                    Button { editingRule = rule } label: {
                        RuleRow(rule: rule)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .brandCard(cornerRadius: 12,
                                       level: rule.lastTriggeredAt != nil ? .critical : nil)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteRules)
            }

            Button {
                addRuleTapped()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.gradient)
                    Text("Add Rule")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .brandCard(cornerRadius: 12)
            }
            .buttonStyle(.plain)
        } header: {
            sectionLabel("Rules (\(server.rules.count))")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    /// Is any active rule for this CheckType currently above its threshold?
    /// Drives the red border + red value color on MetricCard.
    private func isTriggered(_ snap: MetricSnapshot) -> Bool {
        server.rules.contains { rule in
            rule.isEnabled
                && rule.checkType == snap.checkType
                && {
                    guard let v = rule.lastValue else { return false }
                    return rule.thresholdDirection == .above
                        ? v > rule.threshold
                        : v < rule.threshold
                }()
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
