import SwiftUI

/// First-launch tour. Four pages: welcome → privacy → monitoring → CTA.
/// Gated by `@AppStorage("hasCompletedOnboarding")`. After the user taps
/// "Get Started" on the final page, the flag flips and ContentView swaps to
/// ServerListView. The user can re-open onboarding from Settings.
struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding") private var completed: Bool = false
    @State private var page: Int = 0

    /// When true, onboarding was opened from Settings (not first launch).
    /// In that mode the bottom CTA dismisses instead of flipping the flag.
    let isPresentedFromSettings: Bool

    @Environment(\.dismiss) private var dismiss

    init(isPresentedFromSettings: Bool = false) {
        self.isPresentedFromSettings = isPresentedFromSettings
    }

    private struct Page: Identifiable {
        let id: Int
        let icon: String
        let iconColor: Color
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        let bullets: [LocalizedStringKey]
    }

    private var pages: [Page] {
        [
            Page(
                id: 0,
                icon: "server.rack",
                iconColor: .blue,
                title: "Welcome to Server Health",
                body: "Monitor your Linux servers without installing anything on them. Just SSH, just your phone.",
                bullets: []
            ),
            Page(
                id: 1,
                icon: "lock.shield.fill",
                iconColor: .green,
                title: "Your data stays yours",
                body: "Server Health connects directly to your servers. No middleman.",
                bullets: [
                    "Your password is used only once, for initial setup, and never stored.",
                    "The SSH key is generated on this device and stays in your Keychain.",
                    "No third-party servers — connections go from your phone to yours.",
                    "Open source — read every line at github.com/tahaercan/serverhealth"
                ]
            ),
            Page(
                id: 2,
                icon: "bell.badge.fill",
                iconColor: .orange,
                title: "Alerts when it matters",
                body: "Set thresholds for the metrics you care about. Get notified when one fires.",
                bullets: [
                    "Watch CPU, RAM, disk, bandwidth, services, Docker, security updates, and more.",
                    "iOS wakes the app every 15–30 minutes to run your checks.",
                    "Tap any metric to see its trend over the last 24 hours."
                ]
            ),
            Page(
                id: 3,
                icon: "arrow.up.right.circle.fill",
                iconColor: .accentColor,
                title: "Let's add your first server",
                body: "You'll need the host, SSH user, and password. The password is used once to install a key, then forgotten.",
                bullets: []
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { p in
                    pageView(p)
                        .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            bottomBar
        }
        .background(Color(.systemBackground))
        .toolbar {
            if isPresentedFromSettings {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Page rendering

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 20)

                Image(systemName: p.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(p.iconColor)
                    .padding(.top, 30)

                VStack(spacing: 12) {
                    Text(p.title)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(p.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)

                if !p.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(p.bullets.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(p.iconColor)
                                    .font(.callout)
                                Text(line)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        let isLast = page == pages.count - 1
        VStack(spacing: 0) {
            Divider()
            HStack {
                if !isLast {
                    Button("Skip") {
                        finish()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Spacer().frame(width: 60)
                }

                Spacer()

                Button {
                    if isLast {
                        finish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isLast ? "Get Started" : "Next")
                            .font(.body.weight(.semibold))
                        if !isLast {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(minWidth: 140)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    private func finish() {
        if isPresentedFromSettings {
            dismiss()
        } else {
            completed = true
        }
    }
}

#Preview {
    OnboardingView()
}
