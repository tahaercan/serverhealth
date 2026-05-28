import SwiftUI
import UserNotifications
import UIKit

struct SettingsView: View {

    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var pickedCode: String
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showOnboarding: Bool = false

    init() {
        _pickedCode = State(initialValue: LanguageManager.shared.override)
    }

    private static let githubURL = URL(string: "https://github.com/tahaercan/serverhealth")!

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Picker("App Language", selection: $pickedCode) {
                    Text("System").tag("")
                    ForEach(LanguageManager.supported) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: pickedCode) { _, newValue in
                    languageManager.setOverride(newValue)
                }

                if languageManager.pendingRestart {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Restart the app to apply the language change.")
                            .font(.callout)
                    }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("\"System\" follows your device language and falls back to English if unsupported.")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: notifIcon)
                        .font(.title3)
                        .foregroundStyle(notifColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications")
                            .font(.subheadline.weight(.medium))
                        Text(notifStatusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if notifStatus == .notDetermined {
                        Button("Enable") {
                            Task {
                                notifStatus = await NotificationService.requestAuthorization()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if notifStatus == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Server Health sends a local notification when a monitoring rule is triggered. iOS may run background checks every 15–30 minutes.")
            }

            Section {
                Button {
                    showOnboarding = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show app intro")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Replay the first-launch tour")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Link(destination: Self.githubURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.title3)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Source")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("github.com/tahaercan/serverhealth")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("Server Health is free and open source. You can audit every line of code, build it yourself, and contribute.")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notifStatus = await NotificationService.currentStatus()
        }
        .sheet(isPresented: $showOnboarding) {
            NavigationStack {
                OnboardingView(isPresentedFromSettings: true)
            }
        }
    }

    // MARK: - Notification status helpers

    private var notifStatusLabel: LocalizedStringKey {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: return "Enabled"
        case .denied:                                return "Disabled in iOS Settings"
        case .notDetermined:                         return "Not yet requested"
        @unknown default:                            return "Unknown"
        }
    }

    private var notifIcon: String {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: return "bell.fill"
        case .denied:                                return "bell.slash.fill"
        default:                                     return "bell"
        }
    }

    private var notifColor: Color {
        switch notifStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied:                                return .orange
        default:                                     return .secondary
        }
    }
}
