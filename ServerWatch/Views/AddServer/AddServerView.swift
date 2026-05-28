import SwiftUI
import SwiftData
import UIKit

struct AddServerView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = "root"
    @State private var password: String = ""

    @State private var phase: Phase = .form
    @State private var progressStep: ProgressStep = .connect
    @State private var errorMessage: String?

    enum Phase { case form, working, done }

    enum ProgressStep: Int, CaseIterable, Identifiable {
        case connect, generate, deploy, finalize
        var id: Int { rawValue }
        var labelKey: LocalizedStringKey {
            switch self {
            case .connect:  return "Connecting to server…"
            case .generate: return "Generating SSH key…"
            case .deploy:   return "Deploying key to server…"
            case .finalize: return "Clearing password, finishing up…"
            }
        }
    }

    private static let githubURL = URL(string: "https://github.com/tahaercan/serverhealth")!

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .form:    formView
                case .working: workingView
                case .done:    doneView
                }
            }
            .navigationTitle(phase == .working ? "Setup" : "New Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(phase == .working)
                }
            }
        }
        .interactiveDismissDisabled(phase == .working)
    }

    // MARK: - Trust card

    private var trustCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your password is safe")
                        .font(.headline)
                    Text("How we handle credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                trustBullet(
                    icon: "1.circle.fill",
                    title: "Used only for initial setup",
                    detail: "Your password is sent to your server once, to install an SSH key."
                )
                trustBullet(
                    icon: "2.circle.fill",
                    title: "Never stored anywhere",
                    detail: "Not in Keychain, not on disk, not on any server."
                )
                trustBullet(
                    icon: "3.circle.fill",
                    title: "Cleared from memory after setup",
                    detail: "From then on, only the SSH key (stored in this device's Keychain) is used."
                )
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private func trustBullet(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Open source card

    private var openSourceCard: some View {
        Link(destination: Self.githubURL) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.title3)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Source")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Read every line of code — github.com/tahaercan/serverhealth")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
        .listRowBackground(Color.clear)
    }

    // MARK: - Form

    private var formView: some View {
        Form {
            Section { trustCard }

            Section("Server Details") {
                TextField("Name (e.g. Production VPS)", text: $name)
                TextField("Host / IP", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section {
                Button {
                    runSetup()
                } label: {
                    Label("Connect and Set Up", systemImage: "key.horizontal.fill")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            } footer: {
                Text("Tapping this connects to the server once with your password, installs a freshly-generated SSH key, then clears your password from memory.")
            }

            Section { openSourceCard }

            if let err = errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Setup failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout.weight(.semibold))
                        Text(err)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Working

    private var workingView: some View {
        VStack(spacing: 28) {
            ProgressView().controlSize(.large)
            VStack(alignment: .leading, spacing: 10) {
                stepRow(.connect)
                stepRow(.generate)
                stepRow(.deploy)
                stepRow(.finalize)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stepRow(_ step: ProgressStep) -> some View {
        let current = progressStep.rawValue
        let stepIndex = step.rawValue
        HStack(spacing: 10) {
            if stepIndex < current {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if stepIndex == current {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            }
            Text(step.labelKey)
                .foregroundStyle(stepIndex <= current ? .primary : .secondary)
                .font(.callout)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        ContentUnavailableView {
            Label("Ready", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } description: {
            Text("Server added. Password cleared — only the SSH key is used from now on.")
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Validation

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        (Int(port) ?? 0) > 0
    }

    // MARK: - Setup action

    private func runSetup() {
        errorMessage = nil
        phase = .working
        progressStep = .connect

        let portInt = Int(port) ?? 22
        let nameValue = name.trimmingCharacters(in: .whitespaces)
        let hostValue = host.trimmingCharacters(in: .whitespaces)
        let userValue = username.trimmingCharacters(in: .whitespaces)
        let passValue = password
        let comment = SSHService.deviceComment(deviceName: UIDevice.current.name)

        Task { @MainActor in
            let startedAt = Date()
            do {
                progressStep = .connect
                let task = Task.detached(priority: .userInitiated) {
                    try await SSHService.shared.setupSSHKey(
                        host: hostValue,
                        port: portInt,
                        username: userValue,
                        password: passValue,
                        comment: comment
                    )
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                progressStep = .generate
                try? await Task.sleep(nanoseconds: 300_000_000)
                progressStep = .deploy

                let result = try await task.value

                progressStep = .finalize

                let server = Server(
                    name: nameValue,
                    host: hostValue,
                    port: portInt,
                    username: userValue,
                    keychainKeyId: result.keyId
                )
                // Pin the host key fingerprint captured during the
                // password-auth handshake. All future connections will
                // verify against this — a mismatch throws hostKeyMismatch.
                server.hostKeyFingerprint = result.hostKeyFingerprint
                context.insert(server)
                try context.save()

                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                context.insert(LogEntry(
                    server: server,
                    timestamp: .now,
                    kind: .keySetup,
                    checkType: nil,
                    ruleId: nil,
                    command: "ed25519 key generated + deployed to authorized_keys (\(comment))",
                    output: result.publicKeyOpenSSH,
                    errorMessage: nil,
                    value: nil,
                    triggered: false,
                    durationMs: elapsed
                ))
                try? context.save()

                // Clear password from memory (best-effort)
                password = ""

                // Request notification permission at this natural moment —
                // user just configured monitoring, they likely want alerts.
                // requestAuthorization() is idempotent; if already decided,
                // it just returns the current status without prompting again.
                _ = await NotificationService.requestAuthorization()

                try? await Task.sleep(nanoseconds: 250_000_000)
                phase = .done
            } catch {
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                context.insert(LogEntry(
                    server: nil,
                    timestamp: .now,
                    kind: .keySetup,
                    checkType: nil,
                    ruleId: nil,
                    command: "Setup attempt to \(userValue)@\(hostValue):\(portInt) (comment: \(comment))",
                    output: nil,
                    errorMessage: error.localizedDescription,
                    value: nil,
                    triggered: false,
                    durationMs: elapsed
                ))
                try? context.save()

                // Best-effort: clear the password from memory even on failure.
                // Without this, a failed attempt leaves the user's plaintext
                // password sitting in @State until they retype or dismiss the
                // sheet. If the next leak surface (debug print, crash dump,
                // accessibility export) reads @State, this prevents exposure.
                password = ""

                errorMessage = error.localizedDescription
                phase = .form
            }
        }
    }
}
