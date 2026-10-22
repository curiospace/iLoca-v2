//
//  Theme.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//

import SwiftUI
import AppKit

// MARK: - Color palette
// Exact hex values from the landing page reference design.

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Color {
    /// A colour that follows the app's appearance: `light` in Light mode, `dark` in Dark mode.
    init(light: UInt, dark: UInt) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

// Dark values are the original design; light values are tuned for contrast on white.
enum AppColor {
    // Backgrounds
    static let navyBackground = Color(light: 0xF3F5F8, dark: 0x0B131E)
    static let gridLine = Color(light: 0xE1E6ED, dark: 0x162232)

    // Headline gradient stops (left -> right)
    static let gradientTeal = Color(light: 0x2C7F8D, dark: 0x388E9C)
    static let gradientRoyalBlue = Color(light: 0x3B5998, dark: 0x3B5998)
    static let gradientSlate = Color(light: 0x4B5563, dark: 0x4B5563)
    static let gradientAmber = Color(light: 0xB27C1E, dark: 0xD4A359)

    // Subheadline / active nav
    static let mintLight = Color(light: 0x1E7B5A, dark: 0xE0FABD)

    // UI accents
    static let tealAccent = Color(light: 0x16946E, dark: 0x4ECCA3)
    static let footfallPurple = Color(light: 0x6A4FC8, dark: 0x9B87F5)
    static let mutedGrey = Color(light: 0x5C6878, dark: 0x8E9BAE)

    // Text
    /// Main text colour (white on dark, near-black on light). Use `.opacity` for secondary text
    /// and for faint fills/dividers, which then tint correctly in both modes.
    static let textPrimary = Color(light: 0x111A26, dark: 0xFFFFFF)
    /// Text on a tealAccent fill (user chat bubbles).
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x000000)

    static let headlineGradient = LinearGradient(
        colors: [gradientTeal, gradientRoyalBlue, gradientSlate, gradientAmber],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Used by AIPanelView for the on-device AI panel's accent gradient.
    static let intelligenceGradient = LinearGradient(
        colors: [tealAccent, gradientRoyalBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Fonts
// These reference the exact typefaces from the design spec. If the corresponding
// .ttf/.otf files have been added to the project (and registered in Info.plist
// under "Fonts provided by application"), these will render exactly as designed.
// If not present, SwiftUI's Font.custom gracefully falls back to the system font,
// so nothing breaks either way -- it just won't be pixel-perfect until the font
// files are added.

enum AppFont {
    /// Nav links, body copy: Inter (falls back to SF Pro Display equivalent)
    static func nav(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    /// Big headline: Montserrat Bold/ExtraBold, uppercase, tight tracking
    static func headline(_ size: CGFloat) -> Font {
        .custom("Montserrat-ExtraBold", size: size).weight(.heavy)
    }

    /// Subheadline: Montserrat Bold italic
    static func subheadline(_ size: CGFloat) -> Font {
        .custom("Montserrat-Bold", size: size).weight(.bold).italic()
    }

    /// Footer / scroll hint: Roboto Mono, monospaced uppercase
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("RobotoMono-Medium", size: size).weight(weight)
    }
}

// MARK: - Appearance (Light / Dark / System)

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    /// Saved in UserDefaults under this key. Dark is the original design and the default.
    static let storageKey = "appearance"
    static let defaultMode = AppearanceMode.dark

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Applied app-wide so windows, sheets, menus and the map all match.
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
