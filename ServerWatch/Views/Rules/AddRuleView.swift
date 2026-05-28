import SwiftUI
import SwiftData

struct AddRuleView: View {

    let server: Server
    /// Non-nil when editing an existing rule; nil when creating a new one.
    let rule: MonitoringRule?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var checkType: CheckType = .memoryUsage
    @State private var parameter: String = ""
    @State private var thresholdText: String = "80"
    @State private var byteUnit: ByteUnit = .gb
    @State private var direction: ThresholdDirection = .above
    @State private var interval: Int = 15
    @State private var message: String = "{value} {unit}"

    init(server: Server, rule: MonitoringRule? = nil) {
        self.server = server
        self.rule = rule
    }

    // Capabilities + install state for vnstat-required checks
    @State private var capabilities: SSHProbe.ServerCapabilities?
    @State private var isProbing: Bool = false
    @State private var isInstalling: Bool = false
    @State private var installResult: PackageInstaller.Result?
    @State private var showVnstatWarning: Bool = false

    private let intervalOptions: [Int] = [5, 10, 15, 30, 60, 120, 240]

    var body: some View {
        NavigationStack {
            Form {
                Section("Check Type") {
                    Picker("Type", selection: $checkType) {
                        ForEach(CheckType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: checkType) { _, _ in
                        thresholdText = defaultThreshold(for: checkType)
                        direction = defaultDirection(for: checkType)
                        byteUnit = defaultByteUnit(for: checkType)
                        Task { await probeIfNeeded() }
                    }

                    if checkType.needsParameter {
                        TextField(parameterPrompt, text: $parameter)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if let period = checkType.nativePeriod {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.secondary)
                            Text(period.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(period == .monthly
                                 ? String(localized: "Resets at start of month")
                                 : String(localized: "Resets at start of day"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // vnstat install banner if missing
                if checkType.requiresVnstat {
                    vnstatInstallSection
                }

                Section {
                    if checkType.isBoolean {
                        Picker("Trigger when", selection: $direction) {
                            Text("Open / Active (1)").tag(ThresholdDirection.above)
                            Text("Closed / Inactive (0)").tag(ThresholdDirection.below)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } else if checkType.isByteValued {
                        HStack(spacing: 12) {
                            Picker("", selection: $direction) {
                                Text("> above").tag(ThresholdDirection.above)
                                Text("< below").tag(ThresholdDirection.below)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 140)
                            TextField("16", text: $thresholdText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 60)
                            Picker("", selection: $byteUnit) {
                                ForEach(ByteUnit.allCases) { u in
                                    Text(u.rawValue).tag(u)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Picker("", selection: $direction) {
                                Text("> above").tag(ThresholdDirection.above)
                                Text("< below").tag(ThresholdDirection.below)
                            }
                            .pickerStyle(.segmented)
                            TextField("80", text: $thresholdText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            if !checkType.unit.isEmpty {
                                Text(checkType.unit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Threshold")
                } footer: {
                    if checkType.isBoolean {
                        Text("Boolean checks return 0 or 1; just pick the direction.")
                    } else if checkType.isByteValued {
                        Text("Set this to ~80% of your provider's bandwidth quota for an early warning.")
                    }
                }

                Section {
                    Picker("Check frequency", selection: $interval) {
                        ForEach(intervalOptions, id: \.self) { v in
                            Text("\(v) minutes").tag(v)
                        }
                    }
                } footer: {
                    Text("iOS doesn't guarantee background scheduling — this is an approximate lower bound. In practice, checks happen close to this interval.")
                }

                Section {
                    TextField("Notification message", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Notification")
                } footer: {
                    Text("You can use {value} and {unit} as placeholders.\nExample: \"CPU spike: {value}{unit}\"")
                }
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let r = rule {
                    // Edit mode: pre-fill from existing rule.
                    checkType = r.checkType
                    parameter = r.customCommand ?? ""
                    direction = r.thresholdDirection
                    interval = r.intervalMinutes
                    message = r.notificationMessage
                    if r.checkType.isByteValued {
                        let u = ByteUnit(rawValue: r.thresholdUnit) ?? .gb
                        byteUnit = u
                        thresholdText = formatThreshold(u.fromBytes(r.threshold))
                    } else if !r.checkType.isBoolean {
                        thresholdText = formatThreshold(r.threshold)
                    } else {
                        thresholdText = "0"
                    }
                } else {
                    // New mode: use defaults.
                    thresholdText = defaultThreshold(for: checkType)
                    direction = defaultDirection(for: checkType)
                    byteUnit = defaultByteUnit(for: checkType)
                }
                Task { await probeIfNeeded() }
            }
            .alert("vnstat Not Installed", isPresented: $showVnstatWarning) {
                Button("Save Anyway") { save() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This server doesn't have vnstat installed. The rule will be saved but checks will fail until vnstat is set up. You can install it via the Server Requirements section above.")
            }
        }
    }

    // MARK: - vnstat install section

    @ViewBuilder
    private var vnstatInstallSection: some View {
        Section {
            if isProbing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking server…")
                        .foregroundStyle(.secondary)
                }
            } else if let caps = capabilities {
                if caps.hasVnstat && caps.hasJq {
                    Label("vnstat is installed", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else if caps.family == .apt {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("This check needs vnstat on the server",
                              systemImage: "shippingbox")
                            .font(.callout.weight(.medium))

                        Text(PackageInstaller.aptInstallCommand(
                            packages: ["vnstat", "jq"],
                            enableServices: ["vnstat"]
                        ))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)

                        Text("No reboot needed. First data appears 1-2 minutes after install.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            install()
                        } label: {
                            HStack {
                                if isInstalling { ProgressView().controlSize(.small) }
                                Text(isInstalling ? "Installing…" : "Install on server")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isInstalling)

                        if let result = installResult, !result.success, let err = result.errorMessage {
                            Text(err)
                                .font(.caption.monospaced())
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Manual install required", systemImage: "exclamationmark.triangle")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("This server (\(caps.distroPrettyName)) isn't apt-based. Please install vnstat and jq manually, then tap Save.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Check server") {
                    Task { await probeIfNeeded(force: true) }
                }
            }
        } header: {
            Text("Server Requirements")
        }
    }

    private func probeIfNeeded(force: Bool = false) async {
        guard checkType.requiresVnstat else { return }
        if !force, capabilities != nil { return }
        isProbing = true
        defer { isProbing = false }
        do {
            let caps = try await SSHProbe.capabilities(of: server.credentials)
            capabilities = caps
        } catch {
            capabilities = nil
        }
    }

    private func install() {
        isInstalling = true
        Task {
            let result = await PackageInstaller.install(
                packages: ["vnstat", "jq"],
                enableServices: ["vnstat"],
                on: server,
                context: context
            )
            installResult = result
            isInstalling = false
            if result.success {
                // Re-probe to flip the UI from "install" to "installed".
                await probeIfNeeded(force: true)
            }
        }
    }

    // MARK: - Helpers

    private var parameterPrompt: LocalizedStringKey {
        switch checkType {
        case .serviceStatus:        return "Service name (e.g. nginx, postgresql)"
        case .portOpen:             return "Port number (e.g. 443)"
        case .diskUsageCustomPath:  return "Directory path (e.g. /var)"
        case .custom:               return "Full SSH command"
        default:                    return ""
        }
    }

    private var canSave: Bool {
        if !checkType.isBoolean {
            let normalized = thresholdText.replacingOccurrences(of: ",", with: ".")
            guard Double(normalized) != nil else { return false }
        }
        if checkType.needsParameter,
           parameter.trimmingCharacters(in: .whitespaces).isEmpty {
            // bandwidth needsParameter=false ama interface override için optional — burada bloklamayız
            return false
        }
        // Bandwidth için vnstat yoksa save'i bloklama (sunucuda manuel install yapmış olabilir);
        // engine ilk run'da hata loglar, kullanıcı görür.
        return true
    }

    private func attemptSave() {
        // If this check requires vnstat and we've confirmed it's missing → warn before saving.
        // isProbing means the probe hasn't finished yet — allow save; engine will surface the error.
        // capabilities == nil with no probe in progress means probe failed — allow save similarly.
        if checkType.requiresVnstat,
           !isProbing,
           let caps = capabilities,
           !caps.hasVnstat || !caps.hasJq {
            showVnstatWarning = true
            return
        }
        save()
    }

    private func save() {
        let threshold: Double
        if checkType.isBoolean {
            threshold = 0
        } else if checkType.isByteValued {
            // User input is in byteUnit (GB/TB etc.) — convert to BYTES for storage.
            let userValue = Double(thresholdText.replacingOccurrences(of: ",", with: ".")) ?? 0
            threshold = byteUnit.toBytes(userValue)
        } else {
            threshold = Double(thresholdText.replacingOccurrences(of: ",", with: ".")) ?? 0
        }

        let finalMessage = message.trimmingCharacters(in: .whitespaces).isEmpty
            ? "\(checkType.displayName): {value} {unit}"
            : message

        let param = checkType.needsParameter
            ? parameter.trimmingCharacters(in: .whitespaces)
            : nil
        let unitRaw = checkType.isByteValued ? byteUnit.rawValue : ""

        if let existing = rule {
            // Edit mode: mutate the existing rule in-place.
            existing.checkType = checkType
            existing.customCommand = param
            existing.threshold = threshold
            existing.thresholdUnit = unitRaw
            existing.thresholdDirection = direction
            existing.intervalMinutes = interval
            existing.notificationMessage = finalMessage
        } else {
            // New mode: insert a fresh rule.
            let newRule = MonitoringRule(
                server: server,
                checkType: checkType,
                customCommand: param,
                threshold: threshold,
                thresholdUnit: unitRaw,
                thresholdDirection: direction,
                intervalMinutes: interval,
                notificationMessage: finalMessage
            )
            context.insert(newRule)
        }
        try? context.save()
        dismiss()
    }

    /// Format a Double for display in the threshold text field (no trailing ".0").
    private func formatThreshold(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }

    private func defaultThreshold(for type: CheckType) -> String {
        switch type {
        case .memoryUsage, .cpuLoad, .diskUsageRoot, .diskUsageCustomPath, .topCPUProcess:
            return "80"
        case .loadAverage1m, .loadAverage15m:
            return "2.0"
        case .uptime:
            return "0"
        case .zombieProcessCount, .failedLoginAttempts, .sudoUsageCount:
            return "10"
        case .activeConnections, .processCount:
            return "500"
        case .activeSSHSessions:
            return "5"
        case .dockerStoppedContainers, .pendingSecurityUpdates:
            return "0"
        case .dockerRunningContainers:
            return "0"
        case .rebootRequired, .portOpen, .serviceStatus, .custom:
            return "0"
        case .bandwidthMonthly:
            return "16"   // 16 TB monthly typical-ish (with TB unit default)
        case .bandwidthDaily:
            return "500"  // 500 GB daily
        }
    }

    private func defaultDirection(for type: CheckType) -> ThresholdDirection {
        switch type {
        case .serviceStatus, .portOpen:
            return .below
        default:
            return .above
        }
    }

    private func defaultByteUnit(for type: CheckType) -> ByteUnit {
        switch type {
        case .bandwidthMonthly: return .tb
        case .bandwidthDaily:   return .gb
        default:                return .gb
        }
    }
}
