import SwiftUI

/// Paywall shown when a free user tries to exceed their tier limit
/// (2nd server, 4th rule per server) or opens the upgrade entry from Settings.
///
/// Self-contained — takes formatted price strings and action closures so the
/// StoreKit layer can stay decoupled. Wire it up like:
///
///     PaywallView(
///         priceText: purchaseManager.product?.displayPrice ?? "$19.99",
///         monthlyEquivalentText: "≈ $1.67 / month",
///         isPurchasing: purchaseManager.isPurchasing,
///         onPurchase: { await purchaseManager.purchase() },
///         onRestore:  { await purchaseManager.restore() }
///     )
struct PaywallView: View {

    // MARK: - Inputs

    /// Localized formatted price string from StoreKit, e.g. "$19.99 / year"
    /// or "₺499 / yıl". Locale-formatted by Product.displayPrice.
    var priceText: String = "$19.99 / year"

    /// Anchoring helper: the same price expressed per month.
    /// Computed once at product-load time and passed in.
    var monthlyEquivalentText: String = "≈ $1.67 / month"

    var isPurchasing: Bool = false

    /// False when StoreKit hasn't loaded the product yet (network, ASC
    /// propagation delay). Shown in the CTA as a non-tappable state so
    /// taps aren't silently dropped.
    var isProductAvailable: Bool = true

    /// Most recent error message from purchase / restore. When non-nil
    /// the view shows an inline error chip just below the CTA.
    var errorMessage: String? = nil

    var onPurchase: () async -> Void = {}
    var onRestore:  () async -> Void = {}

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundLayer
            ScrollView {
                VStack(spacing: 32) {
                    hero
                    features
                    cta
                }
                .padding(.horizontal, 24)
                .padding(.top, 72)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            dismissButton
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.paywallBase
            LinearGradient(
                colors: [
                    Color.paywallGreen.opacity(0.14),
                    Color.paywallTeal.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
                )
        }
        .padding(.leading, 16)
        .padding(.top, 16)
        .accessibilityLabel("Close")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            ZStack {
                // Soft outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.paywallGreen.opacity(0.40), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 28)

                // Icon disc
                ZStack {
                    Circle()
                        .fill(Color.paywallBase)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.paywallGreen, Color.paywallTeal],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .frame(width: 132, height: 132)

                    Image(systemName: "server.rack")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.paywallGreen, Color.paywallTeal],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay(alignment: .topTrailing) {
                    Text("PRO")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.paywallGreen, Color.paywallTeal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .foregroundStyle(Color.paywallBase)
                        .offset(x: 12, y: -4)
                }
            }

            VStack(spacing: 10) {
                Text("Server Health Pro")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text("Unlimited servers, unlimited rules.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Features

    private var features: some View {
        VStack(spacing: 16) {
            FeatureRow(
                icon: "infinity",
                title: "Unlimited servers",
                subtitle: "Monitor your entire fleet, not just one box."
            )
            FeatureRow(
                icon: "bell.badge.fill",
                title: "Unlimited rules per server",
                subtitle: "Set every threshold that matters to you."
            )
            FeatureRow(
                icon: "sparkles",
                title: "Every future Pro feature",
                subtitle: "All upgrades included with your subscription."
            )
            FeatureRow(
                icon: "heart.fill",
                title: "Support indie open source",
                subtitle: "Help keep Server Health alive — code stays on GitHub."
            )
        }
    }

    // MARK: - CTA + fine print

    private var cta: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(priceText)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(monthlyEquivalentText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.top, 8)

            Button {
                Task { await onPurchase() }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView().tint(Color.paywallBase)
                    } else if !isProductAvailable {
                        Label("Subscription not available", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Start Pro")
                            .font(.body.weight(.semibold))
                    }
                }
                .foregroundStyle(Color.paywallBase)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: isProductAvailable
                            ? [Color.paywallGreen, Color.paywallTeal]
                            : [Color.gray, Color.gray.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(
                    color: (isProductAvailable ? Color.paywallGreen : .clear).opacity(0.35),
                    radius: 16, x: 0, y: 6
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                )
            }
            .disabled(isPurchasing)

            if let errorMessage = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 0.5)
                        )
                )
            }

            Button {
                Task { await onRestore() }
            } label: {
                Text("Restore Purchases")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.top, 2)

            Text("Auto-renews yearly until canceled. Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                Text("All Pro features stay on your device. We don't sell your data.")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.top, 12)
        }
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.paywallGreen.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.paywallGreen.opacity(0.25), lineWidth: 0.5)
                    )
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.paywallGreen, Color.paywallTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Palette

private extension Color {
    /// #0B0F12 — near-black base matching the app icon background.
    static let paywallBase  = Color(red: 0.043, green: 0.059, blue: 0.071)
    /// #3FD68A — primary brand green.
    static let paywallGreen = Color(red: 0.247, green: 0.839, blue: 0.541)
    /// #3FD6C6 — secondary brand teal.
    static let paywallTeal  = Color(red: 0.247, green: 0.839, blue: 0.776)
}

// MARK: - Preview

#Preview("Idle") {
    PaywallView()
}

#Preview("Purchasing") {
    PaywallView(isPurchasing: true)
}
