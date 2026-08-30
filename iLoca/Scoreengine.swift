//
//  OpportunityTier.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// The 4-tier Opportunity Score used consistently across pins, the sidebar legend,
/// and the block detail panel. This replaces the old placeholder 3-color badge
/// (High Vacancy / Verified Data / Standard) with a real weighted composite,
/// built only from data we actually have:
///
///   - Footfall (40%): real hourly pedestrian counts where we have sensor coverage
///     (68 of 544 blocks); everywhere else, honestly treated as "Low" per spec,
///     not hidden or hallucinated.
///   - Vacancy (40%): inverse of vacancy rate — fewer empty shopfronts = higher score.
///   - Business density (20%): active establishments, normalized against the
///     busiest block in the dataset, as a proxy for area vibrancy.
///
/// This is arithmetic, not an AI guess — same principle the AI advisor panel
/// already follows (grounded in real numbers, no fabricated precision).
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

struct OpportunityScore {
    let value: Int          // 0...100
    let tier: OpportunityTier

    /// - Parameters:
    ///   - block: the block being scored
    ///   - maxActiveEstablishments: the busiest block's active-business count in the
    ///     currently loaded dataset, used to normalize the density component.
    static func compute(for block: BlockSummary, maxActiveEstablishments: Int) -> OpportunityScore {
        // Footfall component (0-100): real data where we have it, honestly-low otherwise.
        let footfallScore: Double
        if let peakCount = block.avgPeakCountWeekday, block.pedestrianSensorsCount > 0 {
            // Normalize against a reasonable busy-block ceiling (~800/hr peak observed in block 25 data).
            footfallScore = min(100, (Double(peakCount) / 800.0) * 100)
        } else {
            // No sensor coverage — treated as "Low", not "no data" (per product decision).
            footfallScore = 20
        }

        // Vacancy component (0-100): lower vacancy = higher score.
        let vacancyScore = max(0, 100 - block.vacancyRatePct)

        // Density component (0-100): normalized against the busiest block currently loaded.
        let densityScore: Double = maxActiveEstablishments > 0
            ? (Double(block.activeEstablishments) / Double(maxActiveEstablishments)) * 100
            : 0

        let weighted = (footfallScore * 0.4) + (vacancyScore * 0.4) + (densityScore * 0.2)
        let rounded = Int(weighted.rounded())
        return OpportunityScore(value: rounded, tier: .forScore(rounded))
    }
}