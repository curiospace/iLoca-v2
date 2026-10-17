//
//  BusinessCategory.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// The three business types a founder can pick. Both datasets map onto them the
/// same way, so block-level counts (dataset 2) and individual businesses
/// (dataset 3) always agree:
///   - FnB:      ANZSIC subdivision 45 (food and beverage services), the CLUE
///               "food_and_beverage_services" column
///   - Retail:   ANZSIC subdivisions 39-43 (retail trade), the CLUE "retail_trade" column
///   - Services: every other active industry
enum BusinessCategory: String, CaseIterable, Identifiable {
    case cafe = "FnB"
    case retail = "Retail"
    case services = "Services"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cafe: return "cup.and.saucer.fill"
        case .retail: return "bag.fill"
        case .services: return "wrench.and.screwdriver.fill"
        }
    }

    var color: Color {
        switch self {
        case .cafe: return AppColor.gradientAmber
        case .retail: return Color(hex: 0xB48CF0)
        case .services: return AppColor.gradientTeal
        }
    }

    /// Classifies a 4-digit ANZSIC code from dataset 3. "0000" (vacant space) is
    /// handled by the caller, since a vacancy isn't a business of any type.
    static func categorize(anzsicCode: String) -> BusinessCategory {
        let subdivision = anzsicCode.prefix(2)
        if subdivision == "45" { return .cafe }
        if ["39", "40", "41", "42", "43"].contains(subdivision) { return .retail }
        return .services
    }
}
