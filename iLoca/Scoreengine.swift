//
//  OpportunityTier.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// The 4-tier Opportunity Score used consistently across pins, the sidebar legend,
/// the block detail panel and the Info tab.
enum OpportunityTier: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case moderate = "Moderate"
    case poor = "Poor"

    var range: String {
        switch self {
        case .excellent: return "80–100"
        case .good: return "60–79"
        case .moderate: return "40–59"
        case .poor: return "0–39"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return AppColor.scoreExcellent
        case .good: return AppColor.scoreGood
        case .moderate: return AppColor.scoreModerate
        case .poor: return AppColor.scorePoor
        }
    }

    static func forScore(_ score: Int) -> OpportunityTier {
        switch score {
        case 80...: return .excellent
        case 60..<80: return .good
        case 40..<60: return .moderate
        default: return .poor
        }
    }
}

/// One factor of the Opportunity Score, kept so the UI can show the breakdown
/// ("Why this location?") instead of a single opaque number.
struct ScoreComponent: Identifiable {
    enum Kind: String { case footfall = "Foot traffic", vacancy = "Occupied shopfronts", density = "Business activity" }

    let kind: Kind
    /// Weight from the published formula (0...1).
    let nominalWeight: Double
    /// Weight actually applied after missing factors are removed (0...1).
    let appliedWeight: Double
    /// Factor score 0...100, nil when the data for it doesn't exist.
    let value: Double?
    /// Plain-language explanation of how the value was derived.
    let detail: String
    /// One-line version for dashboard rows, e.g. "919 people/hr vs 1,515 at the busiest blocks".
    var short: String = ""

    var id: String { kind.rawValue }
    var contribution: Double { (value ?? 0) * appliedWeight }
    var isMissing: Bool { value == nil }
}

/// Weighted composite built only from data iLoca actually has. Arithmetic, not
/// an AI guess:
///   - Foot traffic (40%): average hourly pedestrians in the selected time window at
///     the nearest sensor, relative to the busiest 10% of measured blocks.
///   - Occupied shopfronts (40%): 100 minus the vacancy rate.
///   - Business activity (20%): active businesses relative to the busiest 5% of blocks.
/// A block with no pedestrian sensor nearby is scored on the other two factors
/// (weights rescaled) instead of being assumed quiet, and its confidence drops.
struct OpportunityScore {
    static let footfallWeight = 0.4
    static let vacancyWeight = 0.4
    static let densityWeight = 0.2

    let value: Int
    let tier: OpportunityTier
    let components: [ScoreComponent]

    var hasFootfall: Bool { components.contains { $0.kind == .footfall && !$0.isMissing } }

    /// - Parameters:
    ///   - footfall: people per hour in the selected window, nil if no sensor matched.
    ///   - footfallReference: 90th-percentile footfall across measured blocks, same window.
    ///   - densityReference: 95th-percentile active-business count across blocks.
    static func compute(
        block: CityBlock,
        footfall: Double?,
        footfallReference: Double,
        densityReference: Double,
        timeWindowLabel: String
    ) -> OpportunityScore {
        let footfallValue = footfall.map { min(100, $0 / max(footfallReference, 1) * 100) }
        let vacancyValue = max(0, 100 - block.vacancyRatePct)
        let densityValue = min(100, Double(block.activeEstablishments) / max(densityReference, 1) * 100)

        let available = (footfallValue == nil ? 0 : footfallWeight) + vacancyWeight + densityWeight
        func applied(_ w: Double, present: Bool = true) -> Double { present ? w / available : 0 }

        let footfallDetail: String
        if let footfall {
            footfallDetail = String(format: "%.0f people/hr (%@) at the nearest sensor, against %.0f/hr for the busiest 10%% of measured blocks.",
                                    footfall, timeWindowLabel, footfallReference)
        } else {
            footfallDetail = "No pedestrian sensor within \(Int(OpenDataClient.sensorMatchRadius)) m, so this factor is left out and the other two are re-weighted. It is not assumed to be quiet."
        }

        let components = [
            ScoreComponent(kind: .footfall, nominalWeight: footfallWeight,
                           appliedWeight: applied(footfallWeight, present: footfallValue != nil),
                           value: footfallValue, detail: footfallDetail,
                           short: footfall.map { "\(Int($0.rounded()).formatted()) people/hr vs \(Int(footfallReference.rounded()).formatted()) at the busiest blocks" }
                               ?? "No sensor nearby, so left out"),
            ScoreComponent(kind: .vacancy, nominalWeight: vacancyWeight,
                           appliedWeight: applied(vacancyWeight), value: vacancyValue,
                           detail: String(format: "%d of %d premises vacant (%.1f%%). Fewer empty shopfronts suggests a healthier strip.",
                                          block.vacantPremises, block.totalPremises, block.vacancyRatePct),
                           short: String(format: "%d of %d premises vacant (%.0f%%)", block.vacantPremises, block.totalPremises, block.vacancyRatePct)),
            ScoreComponent(kind: .density, nominalWeight: densityWeight,
                           appliedWeight: applied(densityWeight), value: densityValue,
                           detail: String(format: "%d active businesses, against %.0f for the busiest 5%% of blocks.",
                                          block.activeEstablishments, densityReference),
                           short: "\(block.activeEstablishments) active businesses vs \(Int(densityReference.rounded())) at the busiest blocks")
        ]

        let rounded = Int(components.map(\.contribution).reduce(0, +).rounded())
        return OpportunityScore(value: rounded, tier: .forScore(rounded), components: components)
    }
}
