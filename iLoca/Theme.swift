//
//  Theme.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//

import SwiftUI

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

enum AppColor {
    // Backgrounds
    static let navyBackground = Color(hex: 0x0B131E)
    static let gridLine = Color(hex: 0x162232)

    // Headline gradient stops (left -> right)
    static let gradientTeal = Color(hex: 0x388E9C)
    static let gradientRoyalBlue = Color(hex: 0x3B5998)
    static let gradientSlate = Color(hex: 0x4B5563)
    static let gradientAmber = Color(hex: 0xD4A359)

    // Subheadline
    static let mintLight = Color(hex: 0xE0FABD)

    // UI accents
    static let tealAccent = Color(hex: 0x4ECCA3)
    static let mutedGrey = Color(hex: 0x8E9BAE)

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
