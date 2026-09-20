import SwiftUI

/// Selectable look for the main window, menu bar player and desktop mini player.
enum BrisaTheme: String, CaseIterable, Identifiable {
    case sage, dark, light, ocean, warm
    var id: String { rawValue }

    var name: String {
        switch self {
        case .sage: return "Sage"
        case .dark: return "Dark"
        case .light: return "Light"
        case .ocean: return "Ocean"
        case .warm: return "Warm"
        }
    }

    var scheme: ColorScheme { self == .light ? .light : .dark }

    /// Base color for translucent cards and strokes: white on dark themes, black on the light one.
    var surface: Color { self == .light ? .black : .white }

    var accent: Color {
        switch self {
        case .sage: return Color(red: 0.66, green: 0.79, blue: 0.63)
        case .dark: return Color(red: 0.78, green: 0.80, blue: 0.92)
        case .light: return Color(red: 0.17, green: 0.40, blue: 0.28)
        case .ocean: return Color(red: 0.45, green: 0.78, blue: 0.93)
        case .warm: return Color(red: 0.95, green: 0.71, blue: 0.46)
        }
    }

    /// Text and icons drawn on top of a solid accent fill.
    var onAccent: Color { self == .light ? .white : Color.black.opacity(0.82) }

    var background: [Color] {
        switch self {
        case .sage: return [Color(red: 0.045, green: 0.065, blue: 0.07), Color(red: 0.08, green: 0.115, blue: 0.105), Color(red: 0.045, green: 0.055, blue: 0.06)]
        case .dark: return [Color(red: 0.055, green: 0.055, blue: 0.065), Color(red: 0.10, green: 0.10, blue: 0.115), Color(red: 0.05, green: 0.05, blue: 0.06)]
        case .light: return [Color(red: 0.965, green: 0.97, blue: 0.955), Color(red: 0.92, green: 0.94, blue: 0.93), Color(red: 0.95, green: 0.955, blue: 0.965)]
        case .ocean: return [Color(red: 0.02, green: 0.055, blue: 0.105), Color(red: 0.03, green: 0.11, blue: 0.19), Color(red: 0.02, green: 0.05, blue: 0.10)]
        case .warm: return [Color(red: 0.09, green: 0.06, blue: 0.05), Color(red: 0.145, green: 0.095, blue: 0.07), Color(red: 0.08, green: 0.055, blue: 0.05)]
        }
    }

    /// Second background glow (the first one is always the accent).
    var glow: Color {
        switch self {
        case .sage: return .cyan
        case .dark: return Color(red: 0.40, green: 0.42, blue: 0.70)
        case .light: return Color(red: 0.55, green: 0.75, blue: 0.85)
        case .ocean: return Color(red: 0.20, green: 0.40, blue: 0.90)
        case .warm: return Color(red: 0.90, green: 0.40, blue: 0.25)
        }
    }

    /// Opacity of the background glows; softer on the light theme.
    var glowStrength: Double { self == .light ? 0.5 : 1 }

    /// Tint laid over the mini player's material to give it depth.
    var shade: Color { self == .light ? Color.white.opacity(0.45) : Color.black.opacity(0.35) }
}

/// Holds the applied theme and an optional temporary preview.
@MainActor
final class BrisaThemeStore: ObservableObject {
    static let shared = BrisaThemeStore()

    @Published private(set) var selected: BrisaTheme
    @Published var preview: BrisaTheme?

    var current: BrisaTheme { preview ?? selected }

    private init() {
        selected = BrisaTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .sage
    }

    func apply(_ theme: BrisaTheme) {
        selected = theme
        preview = nil
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
    }

    func cancelPreview() { preview = nil }
}

// Views read these at render time; each top-level view observes `BrisaThemeStore.shared` so a change re-renders it.
@MainActor var accent: Color { BrisaThemeStore.shared.current.accent }
@MainActor var surface: Color { BrisaThemeStore.shared.current.surface }
@MainActor var onAccent: Color { BrisaThemeStore.shared.current.onAccent }

/// WCAG contrast ratio between two sRGB colors, used to check that every theme stays readable.
enum ThemeContrast {
    static func ratio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
    }
}
