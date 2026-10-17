import SwiftUI

/// High / Medium / Low confidence in a block's assessment, based on how much
/// data backs it and how current that data is. Shown under the Opportunity
/// Score, in reports, in AI answers and on the Info tab.
enum ConfidenceLevel: String {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: Color {
        switch self {
        case .high: return AppColor.scoreExcellent
        case .medium: return AppColor.scoreModerate
        case .low: return AppColor.scorePoor
        }
    }

    var icon: String {
        switch self {
        case .high: return "checkmark.seal.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "exclamationmark.triangle.fill"
        }
    }

    static func forPoints(_ points: Int) -> ConfidenceLevel {
        switch points {
        case 75...: return .high
        case 50..<75: return .medium
        default: return .low
        }
    }
}

struct ConfidenceFactor: Identifiable {
    let name: String
    let points: Int
    let maxPoints: Int
    let detail: String
    /// One-line version for dashboard rows, e.g. "Sensor 56 m away".
    var short: String = ""
    var id: String { name }
}

struct ConfidenceAssessment {
    let points: Int
    let level: ConfidenceLevel
    let factors: [ConfidenceFactor]

    var summary: String {
        let weakest = factors.min { Double($0.points) / Double($0.maxPoints) < Double($1.points) / Double($1.maxPoints) }
        switch level {
        case .high: return "Well supported by current data."
        case .medium: return "Reasonably supported. Weakest point: \(weakest?.name.lowercased() ?? "n/a")."
        case .low: return "Treat with caution. Weakest point: \(weakest?.name.lowercased() ?? "n/a")."
        }
    }

    /// Scoring rubric (100 points). Kept as data so the Info tab can show it verbatim.
    static let rubric: [(String, Int, String)] = [
        ("Foot-traffic coverage", 40, "Sensor ≤75 m from the block: 40 · ≤150 m: 28 · ≤200 m: 18 · none: 0"),
        ("Sample size", 25, "≥30 premises: 25 · ≥10: 17 · ≥3: 8 · fewer: 2. Vacancy rates on tiny blocks are noisy."),
        ("Business census age", 15, "Census ≤1 year old: 15 · 2 years: 11 · 3 years: 7 · older: 3"),
        ("Foot-traffic recency", 10, "Counts end ≤3 days ago: 10 · ≤10 days: 6 · older: 2 · no sensor: 0"),
        ("Data source", 10, "Live from the City of Melbourne API: 10 · offline copy <24 h old: 7 · older copy: 3")
    ]

    static func assess(
        block: CityBlock,
        censusYear: Int,
        footfallWindowEnd: Date?,
        source: DataSourceState,
        now: Date = Date()
    ) -> ConfidenceAssessment {
        var factors: [ConfidenceFactor] = []

        // 1. Foot-traffic coverage
        if let distance = block.sensorDistanceMetres {
            let pts = distance <= 75 ? 40 : distance <= 150 ? 28 : 18
            factors.append(.init(name: "Foot-traffic coverage", points: pts, maxPoints: 40,
                                 detail: "Nearest pedestrian sensor is \(Int(distance.rounded())) m from the block centre.",
                                 short: "Sensor \(Int(distance.rounded())) m away"))
        } else {
            factors.append(.init(name: "Foot-traffic coverage", points: 0, maxPoints: 40,
                                 detail: "No pedestrian sensor within \(Int(OpenDataClient.sensorMatchRadius)) m, so foot traffic is unknown.",
                                 short: "No sensor within \(Int(OpenDataClient.sensorMatchRadius)) m"))
        }

        // 2. Sample size
        let n = block.totalPremises
        let samplePts = n >= 30 ? 25 : n >= 10 ? 17 : n >= 3 ? 8 : 2
        factors.append(.init(name: "Sample size", points: samplePts, maxPoints: 25,
                             detail: "\(n) premises recorded in this block.",
                             short: "\(n) premises recorded"))

        // 3. Business census age
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
        let age = max(0, currentYear - censusYear)
        let agePts = age <= 1 ? 15 : age == 2 ? 11 : age == 3 ? 7 : 3
        factors.append(.init(name: "Business census age", points: agePts, maxPoints: 15,
                             detail: "Business and vacancy figures come from the \(censusYear) CLUE census (\(age == 0 ? "this year" : "\(age) year\(age == 1 ? "" : "s") old")).",
                             short: "\(censusYear) census"))

        // 4. Foot-traffic recency
        if block.sensorId != nil, let end = footfallWindowEnd {
            let days = max(0, Int(now.timeIntervalSince(end) / 86_400))
            let pts = days <= 3 ? 10 : days <= 10 ? 6 : 2
            factors.append(.init(name: "Foot-traffic recency", points: pts, maxPoints: 10,
                                 detail: "Pedestrian averages run up to \(MelbourneTime.day(end)).",
                                 short: "Counts to \(MelbourneTime.shortDay(end))"))
        } else {
            factors.append(.init(name: "Foot-traffic recency", points: 0, maxPoints: 10,
                                 detail: "No foot-traffic readings for this block.",
                                 short: "No readings"))
        }

        // 5. Data source
        let sourcePts: Int
        let sourceDetail: String
        switch source {
        case .live(let at):
            sourcePts = 10
            sourceDetail = "Fetched live from the City of Melbourne API \(at.formatted(.relative(presentation: .named)))."
        case .cached(let at, let reason):
            sourcePts = now.timeIntervalSince(at) < 86_400 ? 7 : 3
            sourceDetail = "Using the offline copy saved \(at.formatted(.relative(presentation: .named))) (\(reason))."
        case .loading, .unavailable:
            sourcePts = 0
            sourceDetail = "Data source not available."
        }
        let sourceShort: String
        switch source {
        case .live: sourceShort = "Live data"
        case .cached: sourceShort = "Offline copy"
        default: sourceShort = "Unavailable"
        }
        factors.append(.init(name: "Data source", points: sourcePts, maxPoints: 10, detail: sourceDetail, short: sourceShort))

        let total = factors.map(\.points).reduce(0, +)
        return ConfidenceAssessment(points: total, level: .forPoints(total), factors: factors)
    }
}
