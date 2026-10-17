import Foundation

// MARK: - Grounding: turns iLoca's real data into the text the model reads.
// Shared by the Map advisor, the Info assistant and the PDF report, so the AI
// always sees exactly the numbers the UI shows.

enum Grounding {

    static func filtersSummary(_ filters: MapFilterState) -> String {
        var lines: [String] = []
        lines.append("Business type: \(filters.businessCategory?.rawValue ?? "Not chosen")")
        lines.append("Area: \(filters.area ?? "All areas")")
        lines.append("Time window: \(filters.timeWindowLabel)")
        lines.append("Footfall level filter: \(filters.footfallLevel.rawValue)")
        lines.append("Competitor type: \(filters.competitorType.rawValue)")
        lines.append("Search radius: \(filters.searchRadius.label)")
        lines.append("Competition preference: \(filters.competitionPreference.rawValue)")
        return lines.joined(separator: "\n")
    }

    /// - Parameter compact: a shorter version for the on-device model's small context
    ///   window (peaks instead of every hour, fewer named businesses).
    static func blockContext(_ store: CityDataStore, block: CityBlock, includeBusinesses: Bool = true, compact: Bool = false) -> String {
        let filters = store.filters
        var lines: [String] = []
        lines.append("BLOCK \(block.blockId), \(block.area) (City of Melbourne CLUE block)")
        lines.append("Business census year: \(store.censusYear)")
        lines.append("Premises recorded: \(block.totalPremises); active businesses: \(block.activeEstablishments); vacant: \(block.vacantPremises) (\(String(format: "%.1f", block.vacancyRatePct))% vacancy)")
        lines.append("By type: FnB \(block.fnbCount), Retail \(block.retailCount), Services \(block.servicesCount)")

        if !block.industryMix.isEmpty {
            lines.append("Industry mix (CLUE industry: count): " + block.industryMix.sorted { $0.value > $1.value }
                .prefix(compact ? 6 : 20).map { "\($0.key) \($0.value)" }.joined(separator: "; "))
        }

        if let sensor = store.sensor(for: block), let distance = block.sensorDistanceMetres {
            lines.append("\nFOOT TRAFFIC (Pedestrian Counting System, sensor \"\(sensor.description)\", \(Int(distance)) m from the block centre)")
            if let ff = store.footfall(for: block) {
                lines.append("Average for the selected window (\(filters.timeWindowLabel)): \(Int(ff.rounded())) people/hour")
            }
            for day in DayType.allCases {
                if let profile = store.hourlyProfile(for: block, dayType: day) {
                    let peak = profile.enumerated().compactMap { i, v in v.map { (i, $0) } }.max { $0.1 < $1.1 }
                    let hourly = profile.enumerated().compactMap { i, v in v.map { "\(i):00 \(Int($0.rounded()))" } }
                    if let peak {
                        lines.append("\(day.rawValue) peak: \(peak.0):00 at \(Int(peak.1.rounded())) people/hour."
                                     + (compact ? "" : " Hourly averages: \(hourly.joined(separator: ", "))"))
                    }
                }
            }
            if let start = store.snapshot?.footfallWindowStart, let end = store.snapshot?.footfallWindowEnd {
                lines.append("Averaged over \(MelbourneTime.day(start)) to \(MelbourneTime.day(end)).")
            }
        } else {
            lines.append("\nFOOT TRAFFIC: no pedestrian sensor within \(Int(OpenDataClient.sensorMatchRadius)) m, so foot traffic here is unknown (not necessarily low).")
        }

        if let m = store.metrics(for: block) {
            lines.append("\nOPPORTUNITY SCORE: \(m.score.value)/100 (\(m.score.tier.rawValue))")
            for c in m.score.components {
                let v = c.value.map { "\(Int($0.rounded()))/100" } ?? "not available"
                lines.append("- \(c.kind.rawValue): \(v), weight \(Int((c.appliedWeight * 100).rounded()))% (formula weight \(Int(c.nominalWeight * 100))%). \(c.detail)")
            }
            lines.append("\nCOMPETITION: \(m.competitorsInRadius) \(filters.competitorType.rawValue.lowercased()) within \(filters.searchRadius.label) (business type: \(filters.businessCategory?.rawValue ?? "not chosen")). Compared with other blocks this is \(m.competitionBand == .low ? "low" : m.competitionBand == .established ? "high (an established area)" : "about average").")
            if let tier = m.footfallTier { lines.append("Foot-traffic level versus other measured blocks: \(tier.rawValue)") }
        }

        let parking = store.parking(for: block)
        lines.append("\nPARKING within \(filters.searchRadius.label) (context only, not part of the score):")
        if let offStreet = store.snapshot?.offStreet {
            lines.append("- Off-street (\(offStreet.censusYear) census): \(parking.carParks.count) public car parks, \(parking.publicSpaces) public spaces; \(parking.privateSpacesInBlock) private spaces inside this block.")
            for item in parking.carParks.prefix(compact ? 2 : 5) {
                lines.append("  - \(item.carPark.address): \(item.carPark.spaces) spaces, \(Int(item.distance)) m away")
            }
        }
        if let onStreet = store.onStreet {
            if parking.bayCount > 0 {
                lines.append("- On-street sensor bays, live as of \(onStreet.latestReport.map { MelbourneTime.dayTime($0) } ?? "now"): \(parking.freeBays) of \(parking.bayCount) free. Only sensor-fitted bays are counted.")
            } else {
                lines.append("- No sensor-fitted on-street bays within the radius.")
            }
        }

        let confidence = store.confidence(for: block)
        lines.append("\nCONFIDENCE: \(confidence.level.rawValue) (\(confidence.points)/100)")
        for f in confidence.factors { lines.append("- \(f.name): \(f.points)/\(f.maxPoints). \(f.detail)") }

        if includeBusinesses, let premises = store.premisesByBlock[block.blockId] {
            let businesses = premises.filter { !$0.isVacant }
            let vacancies = premises.filter(\.isVacant)
            let limit = compact ? 15 : businesses.count
            lines.append("\nNAMED BUSINESSES IN THIS BLOCK (\(businesses.count) total\(businesses.count > limit ? ", first \(limit) listed" : "")):")
            for b in businesses.prefix(limit) {
                lines.append(compact ? "- \(b.name) (\(b.industry))" : "- \(b.name) [\(b.category?.rawValue ?? "")] \(b.industry), \(b.address)")
            }
            if !vacancies.isEmpty && !compact {
                lines.append("\nVACANT PREMISES (\(vacancies.count)): " + vacancies.prefix(25).map(\.address).joined(separator: "; "))
            }
        } else {
            lines.append("\nNamed business list for this block is still loading, so only the counts above are available right now.")
        }

        lines.append("\nNOT AVAILABLE in iLoca's data: commercial rents, lease terms, property listings, revenue or ROI, public transport, floor space, demographics, zoning or planning approvals. On-street parking covers sensor-fitted bays only.")
        return lines.joined(separator: "\n")
    }

    static func cityOverview(_ store: CityDataStore) -> String {
        let blocks = store.blocks
        guard !blocks.isEmpty else { return "City data hasn't loaded yet." }
        let totalPremises = blocks.map(\.totalPremises).reduce(0, +)
        let vacant = blocks.map(\.vacantPremises).reduce(0, +)
        let active = blocks.map(\.activeEstablishments).reduce(0, +)
        let withSensor = blocks.filter { $0.sensorId != nil }.count

        var lines: [String] = []
        lines.append("CITY-WIDE SUMMARY, City of Melbourne (\(store.censusYear) business census)")
        lines.append("Blocks with commercial premises: \(blocks.count); premises: \(totalPremises); active businesses: \(active); vacant: \(vacant) (\(String(format: "%.1f", Double(vacant) / Double(max(totalPremises, 1)) * 100))%)")
        lines.append("Blocks with a pedestrian sensor within \(Int(OpenDataClient.sensorMatchRadius)) m: \(withSensor) of \(blocks.count)")
        if let offStreet = store.snapshot?.offStreet {
            lines.append("Public off-street car parks (\(offStreet.censusYear) census): \(offStreet.carParks.count), \(offStreet.carParks.map(\.spaces).reduce(0, +)) spaces")
        }
        if let onStreet = store.onStreet {
            let free = onStreet.bays.filter { !$0.isOccupied }.count
            lines.append("On-street sensor bays right now: \(free) of \(onStreet.bays.count) free")
        }

        let byArea = Dictionary(grouping: blocks, by: \.area)
        lines.append("\nBy area (blocks, active businesses, vacancy %, FnB, Retail):")
        for (area, group) in byArea.sorted(by: { $0.key < $1.key }) {
            let p = group.map(\.totalPremises).reduce(0, +), v = group.map(\.vacantPremises).reduce(0, +)
            lines.append("- \(area): \(group.count), \(group.map(\.activeEstablishments).reduce(0, +)), \(String(format: "%.1f", Double(v) / Double(max(p, 1)) * 100))%, \(group.map(\.fnbCount).reduce(0, +)), \(group.map(\.retailCount).reduce(0, +))")
        }

        let ranked = store.visibleBlocks.compactMap { b in store.metrics(for: b).map { (b, $0) } }
            .sorted { $0.1.score.value > $1.1.score.value }
        lines.append("\nTop blocks by Opportunity Score under the current filters (\(store.filters.timeWindowLabel)):")
        for (b, m) in ranked.prefix(12) {
            lines.append("- Block \(b.blockId) (\(b.area)): score \(m.score.value), confidence \(store.confidence(for: b).level.rawValue), \(b.activeEstablishments) active, \(String(format: "%.0f", b.vacancyRatePct))% vacant\(m.footfall.map { ", \(Int($0)) people/hr" } ?? ", no sensor")")
        }
        lines.append("\nCurrent filters:\n\(filtersSummary(store.filters))")
        return lines.joined(separator: "\n")
    }

    static func sources(for block: CityBlock?) -> [String] {
        var sources = [CityDataset.blocks, .industryPerBlock, .establishments].map(\.title)
        if block == nil || block?.sensorId != nil { sources.append("Pedestrian Counting System") }
        sources.append(CityDataset.offStreetParking.title)
        sources.append(CityDataset.onStreetParking.title)
        return sources
    }
}

// MARK: - Map advisor (floating Loca panel on Home + Map)

@Observable
final class LocationAdvisorAI {
    let session = ChatSession()
    private(set) var groundedBlockId: Int?

    var messages: [ChatMessage] { session.messages }

    /// Grounds on the current selection, clearing the chat if the subject changed.
    func reground(store: CityDataStore) {
        if let block = store.selectedBlock {
            groundOnBlock(block, store: store)
        } else {
            groundOnCity(store)
        }
    }

    /// Refreshes grounding with the latest filters and data (same subject keeps
    /// the conversation), then asks.
    func ask(_ question: String, store: CityDataStore) {
        if let block = store.selectedBlock {
            groundOnBlock(block, store: store, keepConversation: true)
        } else {
            groundOnCity(store)
        }
        session.ask(question)
    }

    func groundOnBlock(_ block: CityBlock, store: CityDataStore, keepConversation: Bool = false) {
        let system = Self.blockSystem(Grounding.blockContext(store, block: block))
        let compact = Self.blockSystem(Grounding.blockContext(store, block: block, compact: true))
        let confidence = store.confidence(for: block)
        let provenance = AnswerProvenance(
            sources: Grounding.sources(for: block),
            confidence: confidence.level,
            confidenceNote: confidence.summary,
            notes: decisionNotes(block: block, store: store)
        )
        if keepConversation && groundedBlockId == block.blockId {
            session.updateGrounding(system: system, compactSystem: compact, provenance: provenance)
        } else {
            session.reset(system: system, compactSystem: compact, provenance: provenance)
        }
        groundedBlockId = block.blockId
    }

    private static func blockSystem(_ context: String) -> String {
        """
        You are Loca, a location advisor helping a first-time small business owner decide whether \
        a City of Melbourne block suits their business. Below is iLoca's REAL data for the selected \
        block: City of Melbourne CLUE census figures, live pedestrian sensor averages, and iLoca's \
        own computed Opportunity Score and confidence rating.

        When asked why a score is what it is, explain it using the factor breakdown and weights below. \
        When the confidence is Medium or Low, say so and name the reason. Distances between businesses \
        and walking times are not in the data.

        \(context)
        """
    }

    func groundOnCity(_ store: CityDataStore) {
        let system = """
        You are Loca, a location advisor helping a first-time small business owner explore City of \
        Melbourne blocks. No block is selected yet. Below is REAL city-wide summary data. For block-level \
        detail (named businesses, hourly foot traffic), suggest they select a block on the map.

        \(Grounding.cityOverview(store))
        """
        let provenance = AnswerProvenance(
            sources: Grounding.sources(for: nil),
            notes: ["Answered from city-wide totals and the top-scoring blocks under your current filters."]
        )
        if groundedBlockId == nil && !session.messages.isEmpty {
            session.updateGrounding(system: system, provenance: provenance)
        } else {
            session.reset(system: system, provenance: provenance)
        }
        groundedBlockId = nil
    }

    private func decisionNotes(block: CityBlock, store: CityDataStore) -> [String] {
        guard let m = store.metrics(for: block) else { return [] }
        var notes = ["Opportunity Score \(m.score.value): " + m.score.components.map { c in
            c.value == nil ? "\(c.kind.rawValue.lowercased()) not available"
                : "\(c.kind.rawValue.lowercased()) \(Int(c.value!.rounded())) × \(Int((c.appliedWeight * 100).rounded()))%"
        }.joined(separator: " + ")]
        notes.append("Filters applied: \(store.filters.timeWindowLabel); \(store.filters.businessCategory?.rawValue ?? "no business type"); \(store.filters.searchRadius.label) radius.")
        notes.append("Loca only sees the data listed above. It has no rent, zoning or public transport data.")
        return notes
    }
}
