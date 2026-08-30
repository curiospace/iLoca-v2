//
//  GuideBucket.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

// MARK: - The four SME-journey stages on the Guides page.
// Each maps to one bundled PDF. Add the 4 guide PDFs to the Xcode project
// (drag into the project navigator, "Copy items if needed" + target checked)
// using exactly the file names referenced in `pdfResourceName` below.

enum GuideBucket: String, CaseIterable, Identifiable {
    case plan, setup, budget, grow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .setup: return "Setup"
        case .budget: return "Budget"
        case .grow: return "Grow"
        }
    }

    var subtitle: String {
        switch self {
        case .plan: return "Start and plan your business"
        case .setup: return "City of Melbourne setup & compliance"
        case .budget: return "Cash flow, pricing and viability"
        case .grow: return "Scale, hire and expand"
        }
    }

    var icon: String {
        switch self {
        case .plan: return "lightbulb.fill"
        case .setup: return "building.2.fill"
        case .budget: return "banknote.fill"
        case .grow: return "chart.line.uptrend.xyaxis"
        }
    }

    /// Reuses the exact accents already defined in Theme.swift so this page
    /// stays visually consistent with the landing page and map.
    var accent: Color {
        switch self {
        case .plan: return AppColor.gradientTeal
        case .setup: return AppColor.gradientRoyalBlue
        case .budget: return AppColor.gradientAmber
        case .grow: return AppColor.tealAccent
        }
    }

    /// Bundled PDF resource name (no extension). Must match the file added to
    /// the Xcode project exactly.
    var pdfResourceName: String {
        switch self {
        case .plan: return "plan-guide-to-starting-a-business"
        case .setup: return "setup-city-of-melbourne-business-guide"
        case .budget: return "budget-guide-to-managing-cash-flow"
        case .grow: return "grow-guide-to-growing-your-business"
        }
    }

    var documentTitle: String {
        switch self {
        case .plan: return "Guide to Starting a Business"
        case .setup: return "City of Melbourne: Business Setup & Compliance"
        case .budget: return "Guide to Managing Cash Flow & Pricing for Profit"
        case .grow: return "Guide to Growing Your Business"
        }
    }
}