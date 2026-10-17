import Foundation

/// How iLoca turns data into recommendations. One source of truth for the
/// Info tab's "How Loca decided" section and the Info assistant's grounding.
enum Methodology {
    struct Section: Identifiable {
        let title: String
        let icon: String
        let points: [String]
        var id: String { title }
    }

    static var sections: [Section] {
        [
            Section(title: "Opportunity Score", icon: "gauge.with.dots.needle.50percent", points: [
                "A 0–100 weighted score that Swift computes on your Mac. It's arithmetic, not an AI judgement.",
                "Foot traffic: \(Int(OpportunityScore.footfallWeight * 100))%. Average people per hour at the nearest pedestrian sensor in your chosen time window, compared with the busiest 10% of measured blocks.",
                "Occupied shopfronts: \(Int(OpportunityScore.vacancyWeight * 100))%. 100 minus the block's vacancy rate from the business census.",
                "Business activity: \(Int(OpportunityScore.densityWeight * 100))%. Active businesses compared with the busiest 5% of blocks, as a proxy for how lively the area is.",
                "No sensor within \(Int(OpenDataClient.sensorMatchRadius)) m: the foot-traffic factor is left out and occupied shopfronts and business activity are re-weighted from 40% and 20% to 67% and 33%. The block isn't assumed quiet, and its confidence drops.",
                "Tiers: Excellent 80–100 · Good 60–79 · Moderate 40–59 · Poor 0–39."
            ]),
            Section(title: "Filters", icon: "line.3.horizontal.decrease.circle", points: [
                "Time of Day and Day Type change which hours of pedestrian data are averaged, so the score and footfall levels follow your trading hours. Morning 7–11am, lunch 11am–2pm, afternoon 2–5pm, evening 5–9pm. With nothing selected it covers 7am–9pm, with weekdays and weekends weighted 5:2.",
                "Footfall level splits measured blocks into quarters for the chosen window: Low, Medium, High, Very high. Blocks without a sensor can't match a level.",
                "Competition counts businesses within the search radius of each block: direct (same type as yours), indirect (other types) or all. Competition preference keeps blocks in the bottom, middle or top third of that count.",
                "Business type uses ANZSIC codes: FnB is food and beverage services, Retail is retail trade, and Services is everything else."
            ]),
            Section(title: "Parking", icon: "parkingsign.circle", points: [
                "Public car parks come from the off-street parking census: commercial car parks open to the public, with capacity. Private spaces belong to tenants and staff.",
                "Live on-street parking comes from the City's in-ground bay sensors. Only bays that reported in the last 24 hours are used, and the map refreshes every 5 minutes while the overlay is on.",
                "Counts cover the search radius around the selected block. Only sensor-fitted bays are included, not every kerbside space.",
                "Parking is shown for context and isn't part of the Opportunity Score."
            ]),
            Section(title: "Confidence level", icon: "checkmark.seal", points:
                ConfidenceAssessment.rubric.map { "\($0.0) (\($0.1) pts): \($0.2)" }
                + ["High is 75 or more, Medium is 50–74, Low is under 50. Confidence measures how well the data supports the score, not how good the location is."]
            ),
            Section(title: "Loca, the AI assistant", icon: "sparkles", points: [
                "With a Claude API key set (ANTHROPIC_API_KEY), answers come from Anthropic's Claude (\(ClaudeClient.model)). Without one, they come from Apple's on-device model where it's available.",
                "Each answer is grounded in the same numbers you see on screen: block figures, score breakdown, confidence and the named businesses. Loca is told never to invent figures.",
                "AI answers are labelled as AI-generated. Each one shows its sources and confidence under \"How Loca decided\", and can be read aloud or reported.",
                "Loca provides decision support. It isn't financial, legal or planning advice, and it can't guarantee business success."
            ]),
            Section(title: "Privacy", icon: "lock.shield", points: [
                "Chats are ephemeral. They're kept in memory only, cleared when you change block or press Clear, and never saved to disk.",
                "When Claude is enabled, your question and the block data shown are sent to Anthropic's API to generate the answer. Don't type personal or confidential information.",
                "City data comes from the public City of Melbourne API, and the last successful download is cached on this Mac for offline use.",
                "Issue reports are saved locally and only leave your Mac if you share them."
            ]),
            Section(title: "Limitations", icon: "exclamationmark.triangle", points: [
                "Coverage is the City of Melbourne municipality only.",
                "Business and vacancy figures come from the CLUE census, which is updated about once a year, so recent openings and closures may be missing.",
                "Pedestrian sensors cover mainly the CBD and major streets. Most blocks elsewhere have no foot-traffic reading.",
                "Distances run between block centres, not individual shopfronts.",
                "iLoca has no rent, lease, listing, public transport, demographic or zoning data. A location insight doesn't confirm a premises is permitted for your use, so check with the City of Melbourne planning team."
            ])
        ]
    }

    static var groundingText: String {
        sections.map { s in "\(s.title.uppercased())\n" + s.points.map { "- \($0)" }.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    static func dataSourcesText(_ store: CityDataStore) -> String {
        var lines = ["DATA SOURCES (City of Melbourne Open Data, fetched via the Opendatasoft API)"]
        for dataset in CityDataset.allCases {
            let info = store.datasetInfo(dataset)
            let modified = info?.modified.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "unknown"
            lines.append("- \(dataset.title): \(dataset.usedFor) Portal last modified: \(modified). Licence: \(info?.license ?? "see portal").")
        }
        lines.append("Freshness: \(store.freshnessLine)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Info tab assistant

@Observable
final class InfoAdvisorAI {
    let session = ChatSession()
    private var groundedKey: String?

    func ground(store: CityDataStore) {
        let block = store.selectedBlock
        let key = "\(block?.blockId ?? -1)|\(store.snapshot?.fetchedAt.timeIntervalSince1970 ?? 0)"
        guard key != groundedKey else { return }

        func build(compact: Bool) -> String {
        var system = """
        You are Loca, answering questions on iLoca's Info page about how iLoca works: how the \
        Opportunity Score and confidence level are calculated, where the data comes from and how \
        fresh it is, the AI's role and limits, privacy, and how to report an issue (the "Report an \
        issue" button at the top right of the Info page, or the flag icon under any AI answer). \
        Explain clearly for a non-technical small business owner. Use the methodology and data \
        below. If asked about a specific block's score, use the selected block's breakdown.

        \(Methodology.groundingText)

        \(Methodology.dataSourcesText(store))
        """
        if let block {
            system += "\n\nSELECTED BLOCK\n" + Grounding.blockContext(store, block: block, includeBusinesses: false, compact: compact)
        } else {
            system += "\n\nNo block is selected on the map right now."
        }
        return system
        }
        let system = build(compact: false)
        let compactSystem = build(compact: true)

        let confidence = block.map { store.confidence(for: $0) }
        let provenance = AnswerProvenance(
            sources: ["iLoca methodology"] + CityDataset.allCases.map(\.title),
            confidence: confidence?.level,
            confidenceNote: confidence?.summary,
            notes: ["Answered from iLoca's published scoring and confidence rules" + (block.map { " and Block \($0.blockId)'s breakdown." } ?? ".")]
        )
        // Keep the conversation when only the data refreshed; reset when the block changes.
        if groundedKey?.split(separator: "|").first == key.split(separator: "|").first {
            session.updateGrounding(system: system, compactSystem: compactSystem, provenance: provenance)
        } else {
            session.reset(system: system, compactSystem: compactSystem, provenance: provenance)
        }
        groundedKey = key
    }
}
