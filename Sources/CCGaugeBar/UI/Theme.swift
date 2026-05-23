// Theme.swift — design tokens (colors, fonts, radii) mirroring
// ccgauge-app-design/project/styles.css §--bg-* / --text-* / --indigo / --orange.
//
// All colors auto-adapt to light/dark via Color(NSColor: dynamicProvider:).

import SwiftUI
import AppKit

public enum Theme {

    // MARK: - Colors (dark default · light alt)

    public static let bgBase = Color.dynamic(dark: 0x0A0A0B, light: 0xFFFFFF)
    public static let bgSurface = Color.dynamic(dark: 0x141416, light: 0xF7F7F8)
    public static let bgSurfaceHi = Color.dynamic(dark: 0x1C1C1F, light: 0xEFEFF1)
    public static let bgSurfaceHi2 = Color.dynamic(dark: 0x232327, light: 0xE7E7EA)
    public static let border = Color.dynamic(dark: 0x2A2A2E, light: 0xE5E5E7)
    public static let borderHi = Color.dynamic(dark: 0x36363B, light: 0xD4D4D8)

    public static let textPrimary = Color.dynamic(dark: 0xF4F4F5, light: 0x0A0A0B)
    public static let textSecondary = Color.dynamic(dark: 0xA1A1AA, light: 0x52525B)
    public static let textTertiary = Color.dynamic(dark: 0x71717A, light: 0x71717A)
    public static let textQuaternary = Color.dynamic(dark: 0x52525B, light: 0xA1A1AA)

    public static let indigo = Color.dynamic(dark: 0x818CF8, light: 0x4F46E5)
    public static let indigoStrong = Color.dynamic(dark: 0xA5B4FC, light: 0x3730A3)
    public static let indigoDim = Color.dynamic(dark: 0x4F46E5, light: 0x6366F1)
    public static let indigoBgSoft = Color.dynamic(dark: 0x818CF8, light: 0x4F46E5).opacity(0.14)
    public static let indigoBgSoft2 = Color.dynamic(dark: 0x818CF8, light: 0x4F46E5).opacity(0.20)

    public static let orange = Color.dynamic(dark: 0xFB923C, light: 0xEA580C)
    public static let orangeStrong = Color.dynamic(dark: 0xFDBA74, light: 0xC2410C)

    public static let success = Color.dynamic(dark: 0x34D399, light: 0x059669)
    public static let warning = Color.dynamic(dark: 0xFBBF24, light: 0xD97706)
    public static let danger = Color.dynamic(dark: 0xF87171, light: 0xDC2626)

    public static func providerAccent(_ source: ProviderId) -> Color {
        source == .claude ? indigo : orange
    }

    // MARK: - Radii

    public static let radiusCard: CGFloat = 12
    public static let radiusBtn: CGFloat = 8
    public static let radiusPill: CGFloat = 999

    // MARK: - Fonts
    //
    // SwiftUI's `.system(... design: .rounded)` maps to SF Pro Rounded, which
    // is what the design tokens want for all numeric displays. `monospacedDigit()`
    // on top gives us tabular-nums (`font-variant-numeric: tabular-nums`).

    public static func num(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    public static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Color helpers

extension Color {
    /// Hex int → Color. `0xRRGGBB`.
    public init(hex: Int) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Pair of light / dark variants. The system flips based on
    /// NSApplication.shared.effectiveAppearance and the user's macOS theme.
    public static func dynamic(dark: Int, light: Int) -> Color {
        let nsColor = NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >>  8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
        return Color(nsColor: nsColor)
    }
}

// MARK: - Modifiers

/// Standard card surface: rounded corner, border, surface bg.
public struct CardStyle: ViewModifier {
    var padding: CGFloat = 12
    var radius: CGFloat = Theme.radiusCard
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    public func cardStyle(padding: CGFloat = 12, radius: CGFloat = Theme.radiusCard) -> some View {
        self.modifier(CardStyle(padding: padding, radius: radius))
    }

    public func hoverEffect<Hover: View>(@ViewBuilder hovered: @escaping () -> Hover) -> some View {
        self.modifier(HoverModifier(hovered: hovered))
    }
}

private struct HoverModifier<Hover: View>: ViewModifier {
    @State private var isHovered = false
    let hovered: () -> Hover

    func body(content: Content) -> some View {
        ZStack {
            if isHovered { hovered() }
            content
        }
        .onHover { isHovered = $0 }
    }
}
