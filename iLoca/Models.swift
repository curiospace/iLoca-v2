import Foundation

// MARK: - This file defines the "shapes" of our data.
// Swift reads the JSON files and turns them into these structs automatically.

/// The whole city-wide summary file (all_blocks_summary_v2.json)
struct BlocksSummary: Codable {
    let year: Int
    let blockCount: Int
    let blocks: [BlockSummary]

    enum CodingKeys: String, CodingKey {
        case year
        case blockCount = "block_count"
        case blocks
    }
}

/// One block's summary info (used for the map + list)
struct BlockSummary: Codable, Identifiable {
    let blockId: Int
    let clueSmallArea: String
    let totalEstablishments: Int
    let activeEstablishments: Int
    let vacantCount: Int
    let topIndustries: [String: Int]
    let centroidLat: Double
    let centroidLon: Double
    let pedestrianSensorsCount: Int
    let pedestrianDataConfidence: String?
    let avgPeakHourWeekday: Int?
    let avgPeakCountWeekday: Int?

    // Identifiable requires an "id" — we use the block's own ID
    var id: Int { blockId }

    // Handy computed value: what % of this block is empty shopfronts
    var vacancyRatePct: Double {
        guard totalEstablishments > 0 else { return 0 }
        return (Double(vacantCount) / Double(totalEstablishments)) * 100
    }

    enum CodingKeys: String, CodingKey {
        case blockId = "block_id"
        case clueSmallArea = "clue_small_area"
        case totalEstablishments = "total_establishments"
        case activeEstablishments = "active_establishments"
        case vacantCount = "vacant_count"
        case topIndustries = "top_industries"
        case centroidLat = "centroid_lat"
        case centroidLon = "centroid_lon"
        case pedestrianSensorsCount = "pedestrian_sensors_count"
        case pedestrianDataConfidence = "pedestrian_data_confidence"
        case avgPeakHourWeekday = "avg_peak_hour_weekday"
        case avgPeakCountWeekday = "avg_peak_count_weekday"
    }
}

/// A single real business (used in the detailed block files)
struct Business: Codable, Identifiable {
    let name: String
    let address: String
    let industryAnzsic4: String
    let latitude: Double?
    let longitude: Double?

    var id: String { address } // addresses are unique enough to use as an ID here

    enum CodingKeys: String, CodingKey {
        case name
        case address
        case industryAnzsic4 = "industry_anzsic4"
        case latitude
        case longitude
    }
}

/// The detailed file for one specific block (block25_detailed_v2.json, block804_detailed.json)
struct BlockDetail: Codable {
    let blockId: Int
    let clueSmallArea: String
    let year: Int
    let totalEstablishments: Int
    let activeEstablishments: Int
    let vacantCount: Int
    let vacancyRatePct: Double
    let industryBreakdown: [String: Int]
    let businesses: [Business]

    enum CodingKeys: String, CodingKey {
        case blockId = "block_id"
        case clueSmallArea = "clue_small_area"
        case year
        case totalEstablishments = "total_establishments"
        case activeEstablishments = "active_establishments"
        case vacantCount = "vacant_count"
        case vacancyRatePct = "vacancy_rate_pct"
        case industryBreakdown = "industry_breakdown"
        case businesses
    }
}
