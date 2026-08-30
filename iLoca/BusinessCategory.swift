//
//  BusinessCategory.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// Only 3 categories, matched against real ANZSIC4 industry strings seen in the
/// business establishments data (e.g. "cafes & Restaurants", "Retail Trade",
/// "Clothing Retailing", "Finance/Investment Services", "Pathology & Diagnostic
/// Imaging"). No catch-all "Others" bucket — every real business in the dataset
/// falls into one of these three.
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

    /// Matches a raw ANZSIC4 industry string from the dataset to one of our 3 categories.
    /// Uses substring matching since the real strings vary slightly
    /// (e.g. "cafes & Restaurants" vs "Takeaway Food Services" vs "Specialised Food Retailing").
    static func categorize(_ industry: String) -> BusinessCategory {
        let lower = industry.lowercased()

        let cafeKeywords = ["cafe", "restaurant", "takeaway", "food retailing", "food services", "juice", "coffee"]
        if cafeKeywords.contains(where: { lower.contains($0) }) {
            return .cafe
        }

        let retailKeywords = ["retail", "clothing", "footwear", "jewellery", "grocery", "supermarket", "antique", "goods"]
        if retailKeywords.contains(where: { lower.contains($0) }) {
            return .retail
        }

        // Everything else — finance, health, professional/scientific/technical, etc.
        return .services
    }
}
