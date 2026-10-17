//
//  from.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

// MARK: - Extends the existing AppColor enum from Theme.swift
// These are additive — they don't touch anything already defined there.
// Score tiers reuse tealAccent/gradientAmber where possible for palette consistency,
// and add the two colors the landing page palette didn't need (a rival blue, a poor red).

extension AppColor {
    // Opportunity Score tiers (matches the coloring already used for map pin opportunity hints)
    static let scoreExcellent = tealAccent                  // #4ECCA3 — reused, "Excellent"
    static let scoreGood = Color(light: 0x3366D6, dark: 0x5B8DEF)   // "Good"
    static let scoreModerate = gradientAmber                 // #D4A359 — reused, "Moderate"
    static let scorePoor = Color(light: 0xC7413C, dark: 0xE0605B)   // "Poor"

    // Surfaces for cards/panels sitting on the navy background
    static let panelSurface = Color(light: 0xFFFFFF, dark: 0x0F1A28)
    static let cardSurface = Color(light: 0xFFFFFF, dark: 0x131F2E)
    static let cardBorder = Color(light: 0xDCE2EA, dark: 0x1F2E42)
    static let inactiveText = Color(light: 0x98A3B1, dark: 0x5A6B80)
}