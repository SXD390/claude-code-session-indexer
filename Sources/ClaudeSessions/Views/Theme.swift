import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// A color that resolves differently in light vs dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Design tokens

enum Theme {
    // Surfaces — warm charcoal (dark) / warm cream (light)
    static let windowBase = Color.dynamic(light: 0xFAF7F4, dark: 0x161412)
    static let sidebarBase = Color.dynamic(light: 0xF3EEE8, dark: 0x1A1714)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x201D1A)
    static let cardRaised = Color.dynamic(light: 0xFFFFFF, dark: 0x272320)
    static let field = Color.dynamic(light: 0xF1EBE4, dark: 0x191613)
    static let border = Color.dynamic(light: 0xE8E2DB, dark: 0x2A2622)
    static let borderStrong = Color.dynamic(light: 0xDDD4CA, dark: 0x35302B)
    /// Terminal command block — deep and dark in both appearances.
    static let terminal = Color.dynamic(light: 0x1C1916, dark: 0x0F0D0B)

    // Accent — Claude coral
    static let coral = Color.dynamic(light: 0xC15E38, dark: 0xE38561)
    static let coralHi = Color(hex: 0xE38561)
    static let coralLo = Color(hex: 0xB85433)
    static let coralGradient = LinearGradient(
        colors: [Color(hex: 0xE38561), Color(hex: 0xB85433)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Soft coral tint for fills/selection (adapts opacity per mode at call site).
    static let coralTint = Color.dynamic(light: 0xE0785A, dark: 0xE38561)

    // Running / live green
    static let running = Color(hex: 0x53B36B)

    // Curated project palette — 10 hues balanced for both light & dark.
    static let projectPalette: [Color] = [
        Color(hex: 0xDB6B6B), // red
        Color(hex: 0xD98A52), // orange
        Color(hex: 0xC9A24E), // amber
        Color(hex: 0x93AE52), // olive
        Color(hex: 0x5EAF77), // green
        Color(hex: 0x4CAFA0), // teal
        Color(hex: 0x57A6C9), // cyan
        Color(hex: 0x6E8FD6), // blue
        Color(hex: 0x9B7ED1), // violet
        Color(hex: 0xCB74B0), // pink
    ]

    static func projectColor(for key: String) -> Color {
        projectPalette[stableIndex(key, mod: projectPalette.count)]
    }

    /// FNV-1a — stable across launches (unlike String.hashValue, which is seeded per run).
    static func stableIndex(_ s: String, mod: Int) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % UInt64(mod))
    }
}

// MARK: - Shadows

extension View {
    /// Soft elevation shadow — only visible in light mode; dark mode relies on borders.
    func cardShadow(_ scheme: ColorScheme, radius: CGFloat = 10, y: CGFloat = 3) -> some View {
        shadow(color: scheme == .light ? Color.black.opacity(0.06) : .clear,
               radius: radius, x: 0, y: y)
    }
}

// MARK: - Button styles

struct GradientButtonStyle: ButtonStyle {
    var radius: CGFloat = 9
    func makeBody(configuration: Configuration) -> some View { StyleBody(configuration: configuration, radius: radius) }

    private struct StyleBody: View {
        let configuration: Configuration
        let radius: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Theme.coralGradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.28 : 0.14), lineWidth: 1)
                )
                .brightness(hovering ? 0.05 : 0)
                .shadow(color: Theme.coralLo.opacity(configuration.isPressed ? 0.2 : 0.34),
                        radius: configuration.isPressed ? 2 : 7, y: configuration.isPressed ? 1 : 3)
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.16), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyleBody(configuration: configuration) }

    private struct StyleBody: View {
        let configuration: Configuration
        @Environment(\.colorScheme) private var scheme
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    (hovering ? Theme.cardRaised : Theme.field),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(hovering ? Theme.borderStrong : Theme.border, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.975 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.16), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - Shared badges & chips

/// Pulsing green indicator for a running session.
struct RunningDot: View {
    var size: CGFloat = 8
    @State private var animate = false
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.running)
                .frame(width: size * 1.9, height: size * 1.9)
                .scaleEffect(animate ? 1.35 : 0.7)
                .opacity(animate ? 0 : 0.55)
            Circle()
                .fill(Theme.running)
                .frame(width: size, height: size)
                .shadow(color: Theme.running.opacity(0.7), radius: 2)
        }
        .frame(width: size * 1.9, height: size * 1.9)
        .onAppear {
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

/// Small solid dot in a project's deterministic color.
struct ProjectDot: View {
    let key: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Theme.projectColor(for: key))
            .frame(width: size, height: size)
    }
}

/// Coral "named" pill. Compact = icon only; otherwise icon + label.
struct NamedPill: View {
    var compact: Bool = false
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: compact ? 8 : 10, weight: .bold))
            if !compact {
                Text("Named")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 4 : 4)
        .background(Theme.coralGradient, in: Capsule())
        .shadow(color: Theme.coralLo.opacity(0.35), radius: 2, y: 1)
    }
}

/// Green "running" pill with a pulsing dot.
struct RunningPill: View {
    var body: some View {
        HStack(spacing: 5) {
            RunningDot(size: 6)
            Text("Running")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.running)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.running.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.running.opacity(0.25), lineWidth: 1))
    }
}

/// Compact metadata chip: icon + value.
struct MetaChip: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(tint)
    }
}

/// Right-aligned count badge in tabular figures.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.field, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Stat chip used in the detail hero (icon + value + label).
struct StatChip: View {
    let systemImage: String
    let value: String
    let label: String
    var tint: Color = Theme.coral
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .cardShadow(scheme, radius: 6, y: 2)
    }
}

/// The coral gradient app glyph (Claude-style sunburst).
struct AppGlyph: View {
    var size: CGFloat = 26
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.coralGradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "asterisk")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Theme.coralLo.opacity(0.4), radius: 4, y: 1)
    }
}
