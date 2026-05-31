import SwiftUI
import UserNotifications
import UIKit

struct SettingsView: View {

    @ObservedObject private var languageManager = LanguageManager.shared
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var pickedCode: String
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showOnboarding: Bool = false
    @State private var showPaywall: Bool = false
    @State private var bgDiagnostics: BackgroundDiagnostics.Snapshot = BackgroundDiagnostics.current()

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
            // MARK: - Pro subscription
            Section {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: purchaseManager.isPro ? "checkmark.seal.fill" : "sparkles")
                            .font(.title3)
                            .foregroundStyle(purchaseManager.isPro ? .green : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(purchaseManager.isPro ? "Server Health Pro" : "Upgrade to Pro")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(purchaseManager.isPro
                                 ? "Active subscription — thank you!"
                                 : "Unlock unlimited servers and rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if !purchaseManager.isPro {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if !purchaseManager.isPro {
                    Button {
                        Task { await purchaseManager.restore() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Restore Purchases")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("Subscription")
            }

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
                HStack(spacing: 12) {
                    Image(systemName: bgDiagnostics.runCount > 0 ? "arrow.triangle.2.circlepath" : "clock.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(bgDiagnostics.runCount > 0 ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic checks")
                            .font(.subheadline.weight(.medium))
                        if bgDiagnostics.runCount > 0, let last = bgDiagnostics.lastRunAt {
                            Text("\(bgDiagnostics.runCount) total — last \(last.formatted(.relative(presentation: .numeric)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("iOS hasn't fired one yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                if let next = bgDiagnostics.lastScheduledAt {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next check requested")
                                .font(.subheadline.weight(.medium))
                            Text(next.formatted(.relative(presentation: .numeric)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                if let err = bgDiagnostics.lastScheduleError {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Background")
            } footer: {
                Text("iOS decides when to run background checks. We schedule them eagerly (every ~10 min minimum) but Apple's system often delays or skips runs to save battery — especially overnight, on cellular, or for apps the user hasn't opened in a while. For guaranteed cadence, a server-side monitor is the right tool.")
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
            bgDiagnostics = BackgroundDiagnostics.current()
        }
        .sheet(isPresented: $showOnboarding) {
            NavigationStack {
                OnboardingView(isPresentedFromSettings: true)
            }
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
