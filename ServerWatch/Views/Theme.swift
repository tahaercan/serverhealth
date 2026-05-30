import SwiftUI

/// App-wide brand palette + reusable view helpers, so every screen speaks
/// the same visual language as the paywall: dark-first, gradient accents,
/// soft glows, capsule status badges, material-backed cards.
///
/// Colors come from the app icon. Use the named accessors (`.brandGreen`,
/// `.brandTeal`, `.brandBase`) anywhere, and the gradient/badge/card
/// helpers when building screens.
enum Brand {
    /// #3FD68A — primary brand accent (alerts, primary CTAs, status OK).
    static let green = Color(red: 0.247, green: 0.839, blue: 0.541)
    /// #3FD6C6 — secondary accent (gradient companion, highlights).
    static let teal  = Color(red: 0.247, green: 0.839, blue: 0.776)
    /// #0B0F12 — near-black base used by the icon and the paywall.
    /// Other screens use system-adaptive backgrounds so light mode users
    /// aren't forced into dark.
    static let base  = Color(red: 0.043, green: 0.059, blue: 0.071)

    /// Standard brand gradient — used by primary CTAs, icon backgrounds,
    /// status pills, and any "this is the brand" moment.
    static let gradient = LinearGradient(
        colors: [green, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Very low-opacity version of the gradient — for card highlights,
    /// hero header tints, hover/pressed states.
    static let subtleGradient = LinearGradient(
        colors: [green.opacity(0.16), teal.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Status color

/// Health states that drive coloring across the app. Map your data state
/// to one of these and feed it to `statusColor()` for consistent meaning.
enum StatusLevel {
    case ok            // green
    case info          // blue/teal — informational
    case warning       // orange — non-critical attention
    case critical      // red — rule triggered, server unreachable
    case neutral       // gray — never checked, paused

    var color: Color {
        switch self {
        case .ok:       return Brand.green
        case .info:     return Brand.teal
        case .warning:  return .orange
        case .critical: return .red
        case .neutral:  return .secondary
        }
    }
}

// MARK: - Card surface

extension View {
    /// Standard rounded card surface — material background + hairline
    /// stroke + soft shadow. Use on dashboard cards, metric tiles,
    /// hero sections. Pass an explicit `level` to tint the stroke with
    /// the status color (e.g. red border on a triggered rule).
    func brandCard(
        cornerRadius: CGFloat = 16,
        level: StatusLevel? = nil
    ) -> some View {
        let strokeColor: Color = level.map { $0.color.opacity(0.45) }
            ?? .white.opacity(0.06)
        let strokeWidth: CGFloat = (level == nil) ? 0.5 : 1
        let shadowColor: Color = level.map { $0.color.opacity(0.25) }
            ?? .black.opacity(0.18)
        let shadowRadius: CGFloat = (level == nil) ? 10 : 14
        return self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(strokeColor, lineWidth: strokeWidth)
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 4)
        )
    }

    /// Hero card variant — adds the subtle brand gradient over the
    /// material so it reads as the screen's primary surface.
    func brandHeroCard(cornerRadius: CGFloat = 20) -> some View {
        self.background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Brand.subtleGradient)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Brand.green.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: Brand.green.opacity(0.20), radius: 16, x: 0, y: 6)
        )
    }
}

// MARK: - Status pill

/// Small colored capsule with a glyph + label — used on server cards,
/// metric tiles, rule rows to surface state at a glance.
struct StatusPill: View {
    let icon: String
    let text: LocalizedStringKey
    let level: StatusLevel

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(level.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(level.color.opacity(0.15))
                .overlay(Capsule().stroke(level.color.opacity(0.35), lineWidth: 0.5))
        )
    }
}

// MARK: - Brand glyph wrapper

/// SF Symbol in a small rounded square with the brand gradient — used as
/// the leading icon on feature rows, settings sections, etc. Echoes the
/// paywall's feature-row icon treatment.
struct BrandGlyph: View {
    let icon: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Brand.green.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Brand.green.opacity(0.25), lineWidth: 0.5)
                )
            Image(systemName: icon)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Brand.gradient)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Subtle screen background

/// Soft brand-tinted screen background. Use as the bottom layer of any
/// branded screen: `ZStack { BrandBackground(); content }`. Adapts to
/// light/dark via system colors, so users keep their appearance choice.
struct BrandBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                colors: [
                    Brand.green.opacity(0.05),
                    Brand.teal.opacity(0.03),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}
