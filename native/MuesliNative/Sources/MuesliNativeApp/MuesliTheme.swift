import AppKit
import SwiftUI
import MuesliCore

struct ThemeColorPair {
    let dark: Int
    let light: Int
}

struct ThemePalette {
    let backgroundDeep: ThemeColorPair
    let backgroundBase: ThemeColorPair
    let backgroundRaised: ThemeColorPair
    let backgroundHover: ThemeColorPair
    let surfacePrimary: ThemeColorPair
    let surfaceSelected: ThemeColorPair
    let surfaceBorderDarkAlpha: CGFloat
    let surfaceBorderLightAlpha: CGFloat
    let textPrimaryDarkAlpha: CGFloat
    let textPrimaryLightAlpha: CGFloat
    let textSecondaryDarkAlpha: CGFloat
    let textSecondaryLightAlpha: CGFloat
    let textTertiaryDarkAlpha: CGFloat
    let textTertiaryLightAlpha: CGFloat
}

enum MuesliTheme {
    static var currentThemePreset: ThemePreset = .warm

    private static var palette: ThemePalette {
        palette(for: currentThemePreset)
    }

    static func palette(for preset: ThemePreset) -> ThemePalette {
        switch preset {
        case .warm:
            return ThemePalette(
                backgroundDeep: ThemeColorPair(dark: 0x14110E, light: 0xECE5D5),
                backgroundBase: ThemeColorPair(dark: 0x1B1815, light: 0xFAF7F0),
                backgroundRaised: ThemeColorPair(dark: 0x23201C, light: 0xF3EDE1),
                backgroundHover: ThemeColorPair(dark: 0x2B2722, light: 0xE7DECC),
                surfacePrimary: ThemeColorPair(dark: 0x28241F, light: 0xEAE1CF),
                surfaceSelected: ThemeColorPair(dark: 0x3C3328, light: 0xD5C4A8),
                surfaceBorderDarkAlpha: 0.08,
                surfaceBorderLightAlpha: 0.08,
                textPrimaryDarkAlpha: 0.94,
                textPrimaryLightAlpha: 0.88,
                textSecondaryDarkAlpha: 0.66,
                textSecondaryLightAlpha: 0.57,
                textTertiaryDarkAlpha: 0.42,
                textTertiaryLightAlpha: 0.34
            )
        case .neutral:
            return ThemePalette(
                backgroundDeep: ThemeColorPair(dark: 0x0F0F0E, light: 0xE8E6E1),
                backgroundBase: ThemeColorPair(dark: 0x161615, light: 0xF6F5F1),
                backgroundRaised: ThemeColorPair(dark: 0x1D1D1C, light: 0xEFEDE7),
                backgroundHover: ThemeColorPair(dark: 0x252523, light: 0xE0DDD6),
                surfacePrimary: ThemeColorPair(dark: 0x222220, light: 0xE5E2DB),
                surfaceSelected: ThemeColorPair(dark: 0x34332F, light: 0xC8C5BD),
                surfaceBorderDarkAlpha: 0.07,
                surfaceBorderLightAlpha: 0.08,
                textPrimaryDarkAlpha: 0.92,
                textPrimaryLightAlpha: 0.88,
                textSecondaryDarkAlpha: 0.62,
                textSecondaryLightAlpha: 0.55,
                textTertiaryDarkAlpha: 0.40,
                textTertiaryLightAlpha: 0.33
            )
        case .graphite:
            return ThemePalette(
                backgroundDeep: ThemeColorPair(dark: 0x0A0D12, light: 0xDEE3EA),
                backgroundBase: ThemeColorPair(dark: 0x11151C, light: 0xF4F6F9),
                backgroundRaised: ThemeColorPair(dark: 0x181D26, light: 0xEAEEF3),
                backgroundHover: ThemeColorPair(dark: 0x1F2530, light: 0xDAE1E9),
                surfacePrimary: ThemeColorPair(dark: 0x1C2230, light: 0xE0E6EE),
                surfaceSelected: ThemeColorPair(dark: 0x2A3344, light: 0xC2CDDA),
                surfaceBorderDarkAlpha: 0.08,
                surfaceBorderLightAlpha: 0.09,
                textPrimaryDarkAlpha: 0.93,
                textPrimaryLightAlpha: 0.87,
                textSecondaryDarkAlpha: 0.64,
                textSecondaryLightAlpha: 0.56,
                textTertiaryDarkAlpha: 0.42,
                textTertiaryLightAlpha: 0.36
            )
        }
    }

    // MARK: - Colors — Backgrounds (layered)

    static var backgroundDeep: Color { adaptive(pair: palette.backgroundDeep) }
    static var backgroundBase: Color { adaptive(pair: palette.backgroundBase) }
    static var backgroundRaised: Color { adaptive(pair: palette.backgroundRaised) }
    static var backgroundHover: Color { adaptive(pair: palette.backgroundHover) }

    // MARK: - Surfaces (interactive elements)

    static var surfacePrimary: Color { adaptive(pair: palette.surfacePrimary) }
    static var surfaceSelected: Color { adaptive(pair: palette.surfaceSelected) }
    static var surfaceBorder: Color {
        Color.adaptiveAlpha(
            dark: NSColor.white,
            darkAlpha: palette.surfaceBorderDarkAlpha,
            light: NSColor.black,
            lightAlpha: palette.surfaceBorderLightAlpha
        )
    }

    // MARK: - Text hierarchy

    static var textPrimary: Color {
        Color.adaptiveAlpha(
            dark: NSColor.white,
            darkAlpha: palette.textPrimaryDarkAlpha,
            light: NSColor.black,
            lightAlpha: palette.textPrimaryLightAlpha
        )
    }
    static var textSecondary: Color {
        Color.adaptiveAlpha(
            dark: NSColor.white,
            darkAlpha: palette.textSecondaryDarkAlpha,
            light: NSColor.black,
            lightAlpha: palette.textSecondaryLightAlpha
        )
    }
    static var textTertiary: Color {
        Color.adaptiveAlpha(
            dark: NSColor.white,
            darkAlpha: palette.textTertiaryDarkAlpha,
            light: NSColor.black,
            lightAlpha: palette.textTertiaryLightAlpha
        )
    }

    // MARK: - Accent

    static let defaultAccentDarkHex = 0x6BA3F7
    static let defaultAccentLightHex = 0x2563EB
    static let defaultAccent = Color.adaptive(dark: defaultAccentDarkHex, light: defaultAccentLightHex)
    static var accentOverrideHex: String?
    static var accent: Color {
        if let hex = accentOverrideHex, !hex.isEmpty,
           let val = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
            return Color(hex: Int(val))
        }
        return defaultAccent
    }
    static var accentSubtle: Color { accent.opacity(0.15) }

    // MARK: - Semantic

    static let recording = Color(hex: 0xEF4444)
    static let transcribing = Color(hex: 0xF59E0B)
    static let success = Color(hex: 0x34D399)

    // MARK: - Typography (SF Pro via .system())

    static func title1() -> Font { .system(size: 28, weight: .bold) }
    static func title2() -> Font { .system(size: 22, weight: .semibold) }
    static func title3() -> Font { .system(size: 18, weight: .semibold) }
    static func headline() -> Font { .system(size: 15, weight: .semibold) }
    static func body() -> Font { .system(size: 14, weight: .regular) }
    static func callout() -> Font { .system(size: 13, weight: .regular) }
    static func caption() -> Font { .system(size: 12, weight: .regular) }
    static func captionMedium() -> Font { .system(size: 12, weight: .medium) }

    // MARK: - Spacing (4pt grid)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner radii

    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
    static let cornerLarge: CGFloat = 14
    static let cornerXL: CGFloat = 20

    static func nsBackgroundColor() -> NSColor {
        adaptiveNSColor(pair: palette.backgroundBase)
    }

    private static func adaptive(pair: ThemeColorPair) -> Color {
        Color.adaptive(dark: pair.dark, light: pair.light)
    }

    private static func adaptiveNSColor(pair: ThemeColorPair) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.dark : pair.light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        }
    }
}

// MARK: - Color Helpers

extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0
            )
        })
    }

    static func adaptiveAlpha(dark: NSColor, darkAlpha: CGFloat, light: NSColor, lightAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.withAlphaComponent(darkAlpha)
                : light.withAlphaComponent(lightAlpha)
        })
    }
}
