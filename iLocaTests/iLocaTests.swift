//
//  iLocaTests.swift
//  iLocaTests
//
//  Created by Afrah Khan on 29/8/2026.
//

import Foundation
import Testing
import AVFoundation
@testable import iLoca

@MainActor
struct ScoringTests {

    private func block(premises: Int = 50, vacant: Int = 10, active: Int = 40, sensorDistance: Double? = 60) -> CityBlock {
        CityBlock(blockId: 1, area: "Melbourne (CBD)", centroidLat: -37.81, centroidLon: 144.96,
                  fnbCount: 10, retailCount: 8, activeEstablishments: active,
                  totalPremises: premises, vacantPremises: vacant, industryMix: [:],
                  sensorId: sensorDistance == nil ? nil : 7, sensorDistanceMetres: sensorDistance)
    }

    @Test func scoreUsesPublishedWeights() {
        // footfall 50/100, vacancy 80/100, density 40/100 -> 0.4*50 + 0.4*80 + 0.2*40 = 60
        let score = OpportunityScore.compute(block: block(), footfall: 400, footfallReference: 800,
                                             densityReference: 100, timeWindowLabel: "test")
        #expect(score.value == 60)
        #expect(score.tier == .good)
        #expect(score.components.map(\.appliedWeight) == [0.4, 0.4, 0.2])
    }

    @Test func missingFootfallIsExcludedNotZeroed() {
        let score = OpportunityScore.compute(block: block(sensorDistance: nil), footfall: nil, footfallReference: 800,
                                             densityReference: 100, timeWindowLabel: "test")
        // Re-weighted 2/3 vacancy + 1/3 density: 80*2/3 + 40/3 = 66.7
        #expect(score.value == 67)
        #expect(!score.hasFootfall)
        let footfall = score.components.first { $0.kind == .footfall }!
        #expect(footfall.isMissing && footfall.appliedWeight == 0)
    }

    @Test func footfallIsCappedAtReference() {
        let score = OpportunityScore.compute(block: block(), footfall: 5000, footfallReference: 800,
                                             densityReference: 100, timeWindowLabel: "test")
        #expect(score.components.first { $0.kind == .footfall }?.value == 100)
    }

    @Test func confidenceReflectsCoverageAndSampleSize() {
        let now = Date()
        let strong = ConfidenceAssessment.assess(block: block(), censusYear: Calendar.current.component(.year, from: now),
                                                 footfallWindowEnd: now, source: .live(now), now: now)
        #expect(strong.level == .high)
        #expect(strong.points == 100)

        let noSensor = ConfidenceAssessment.assess(block: block(sensorDistance: nil), censusYear: 2024,
                                                   footfallWindowEnd: now, source: .live(now), now: now)
        #expect(noSensor.level == .low)

        let tiny = ConfidenceAssessment.assess(block: block(premises: 2, vacant: 1, active: 1, sensorDistance: 180),
                                               censusYear: 2024, footfallWindowEnd: now,
                                               source: .cached(now.addingTimeInterval(-3 * 86_400), reason: "offline"), now: now)
        #expect(tiny.level == .low)
        #expect(tiny.factors.map(\.maxPoints).reduce(0, +) == 100)
    }

    @Test func footfallBlendsWeekdaysAndWeekendsFiveToTwo() {
        var weekday = [Double?](repeating: nil, count: 24)
        var weekend = [Double?](repeating: nil, count: 24)
        weekday[12] = 700; weekend[12] = 350
        let sensor = PedestrianSensor(locationId: 1, name: "S", description: "S", latitude: 0, longitude: 0,
                                      weekdayHourly: weekday, weekendHourly: weekend)
        #expect(CityDataStore.footfall(sensor: sensor, hours: [12], dayTypes: []) == 600)
        #expect(CityDataStore.footfall(sensor: sensor, hours: [12], dayTypes: [.weekend]) == 350)
        #expect(CityDataStore.footfall(sensor: sensor, hours: [3], dayTypes: []) == nil)
    }

    @Test func timeOfDayHours() {
        let filters = MapFilterState()
        #expect(filters.selectedHours == Array(7...20))
        filters.timesOfDay = [.lunch]
        #expect(filters.selectedHours == [11, 12, 13])
    }

    @Test func percentileInterpolates() {
        #expect(CityDataStore.percentile([0, 10, 20, 30, 40], 0.5) == 20)
        #expect(CityDataStore.percentile([0, 10], 0.25) == 2.5)
        #expect(CityDataStore.percentile([], 0.5) == nil)
    }

    @Test func anzsicCategoriesMatchCLUEColumns() {
        #expect(BusinessCategory.categorize(anzsicCode: "4511") == .cafe)      // Cafes and restaurants
        #expect(BusinessCategory.categorize(anzsicCode: "4253") == .retail)    // Watch and jewellery retailing
        #expect(BusinessCategory.categorize(anzsicCode: "4110") == .retail)    // Supermarkets
        #expect(BusinessCategory.categorize(anzsicCode: "6931") == .services)  // Legal services
    }
}

/// Hits the live City of Melbourne API. Exercises the real data pipeline end to end.
@MainActor
struct LiveDataTests {
    @Test(.timeLimit(.minutes(2))) func snapshotLoadsAllFourDatasets() async throws {
        let snapshot = try await OpenDataClient().fetchSnapshot()
        #expect(snapshot.censusYear >= 2024)
        #expect(snapshot.blocks.count > 400)
        #expect(snapshot.sensors.filter(\.hasCounts).count > 50)
        #expect(snapshot.blocks.contains { $0.sensorId != nil })
        #expect(snapshot.blocks.allSatisfy { $0.vacantPremises <= $0.totalPremises })
        #expect(snapshot.datasets.count == CityDataset.allCases.count)
        let offStreet = try #require(snapshot.offStreet)
        #expect(offStreet.carParks.count > 50)
        #expect(offStreet.carParks.allSatisfy { $0.spaces > 0 })

        // Dataset 2 (category counts) and dataset 3 (premises) must agree for a known CBD block.
        let block25 = try #require(snapshot.blocks.first { $0.blockId == 25 })
        let premises = try await OpenDataClient().fetchPremises(blockId: 25, censusYear: snapshot.censusYear)
        #expect(premises.count == block25.totalPremises)
        #expect(premises.filter(\.isVacant).count == block25.vacantPremises)
        #expect(premises.filter { $0.category == .cafe }.count == block25.fnbCount)
    }
}

/// Recorded Messages API stream events, including thinking and fallback blocks
/// that must not leak into the visible answer.
@MainActor
struct ClaudeStreamParserTests {
    private let normal = [
        "event: message_start",
        #"data: {"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5"}}"#,
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#,
        #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Block 25 "}}"#,
        "",
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"looks busy."}}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#,
        #"data: {"type":"message_stop"}"#
    ]

    @Test func collectsOnlyTextDeltas() throws {
        var parser = ClaudeStreamParser()
        let text = try normal.compactMap { try parser.consume($0) }.joined()
        #expect(text == "Block 25 looks busy.")
        #expect(parser.stopReason == "end_turn")
        try parser.finish()
    }

    @Test func refusalThrowsAfterStream() throws {
        var parser = ClaudeStreamParser()
        _ = try parser.consume(#"data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}}"#)
        #expect(throws: ClaudeError.self) { try parser.finish() }
        #expect(parser.refusalCategory == "cyber")
    }

    @Test func streamErrorEventThrows() {
        var parser = ClaudeStreamParser()
        #expect(throws: ClaudeError.self) {
            try parser.consume(#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
    }

    @Test func fallbackBlockIsIgnored() throws {
        var parser = ClaudeStreamParser()
        let out = try parser.consume(#"data: {"type":"content_block_start","index":0,"content_block":{"type":"fallback","from":{"model":"claude-opus-5-5"},"to":{"model":"claude-opus-4-8"}}}"#)
        #expect(out == nil)
    }
}

/// End-to-end: live data -> grounding -> ChatSession -> LocaAI (Claude if a key is set,
/// otherwise the on-device model). Skipped when no model is available.
@MainActor
struct ChatPipelineTests {
    @Test(.timeLimit(.minutes(3))) func groundedAnswerArrives() async throws {
        let ai = LocaAI.shared
        ai.refresh()
        guard ai.provider.isAvailable else { return }

        let store = CityDataStore()
        await store.load()
        store.filters.businessCategory = .cafe
        store.filters.timesOfDay = [.lunch]
        store.selectedBlockId = 25
        await store.loadPremises(for: 25)

        let advisor = LocationAdvisorAI()
        advisor.reground(store: store)
        advisor.ask("In two sentences: why does this block have its Opportunity Score, and how confident is it?", store: store)
        while advisor.session.isThinking { try await Task.sleep(for: .milliseconds(200)) }

        let reply = try #require(advisor.session.messages.last)
        try? "PROVIDER: \(reply.provider ?? "-")\nANSWER: \(reply.text)"
            .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("iloca_chat_test.txt"), atomically: true, encoding: .utf8)
        #expect(!reply.isUser)
        #expect(!reply.isError)
        #expect(!reply.text.isEmpty)
        #expect(reply.provenance?.confidence == store.confidence(for: store.selectedBlock!).level)
    }
}

@MainActor
struct ParkingTests {
    @Test(.timeLimit(.minutes(1))) func liveBaysLoadAndAggregate() async throws {
        let parking = try await OpenDataClient().fetchOnStreetParking()
        #expect(parking.bays.count > 1000)
        #expect(Set(parking.bays.map(\.kerbsideId)).count == parking.bays.count)
        let latest = try #require(parking.latestReport)
        #expect(Date().timeIntervalSince(latest) < 86_400)

        let store = CityDataStore()
        await store.load()
        await store.refreshOnStreetIfStale()
        let block = try #require(store.block(id: 25))
        let summary = store.parking(for: block)
        #expect(summary.carParks.count > 0)          // CBD block: public car parks within 500 m
        #expect(summary.bayCount >= summary.freeBays)
        let occupancy = store.bayOccupancyByBlock()
        #expect(occupancy.values.map(\.total).reduce(0, +) <= parking.bays.count)
        #expect(!occupancy.isEmpty)
    }
}

@MainActor
struct ReportTests {
    @Test(.timeLimit(.minutes(2))) func pdfRendersFromLiveBlock() async throws {
        let store = CityDataStore()
        await store.load()
        let block = try #require(store.block(id: 25))
        await store.loadPremises(for: 25)
        let attributed = ReportDocumentBuilder.buildAttributedString(.init(
            block: block,
            metrics: try #require(store.metrics(for: block)),
            confidence: store.confidence(for: block),
            filtersSummary: Grounding.filtersSummary(store.filters),
            premises: store.premisesByBlock[25],
            narrative: "Test narrative.",
            aiProvider: "Test",
            censusYear: store.censusYear,
            freshness: store.freshnessLine,
            datasets: store.snapshot?.datasets ?? [],
            parking: store.parking(for: block),
            parkingNote: ""
        ))
        #expect(attributed.string.contains("Confidence"))
        #expect(attributed.string.contains("Vacant Premises"))
        let pdf = ReportPDFRenderer.render(attributedString: attributed)
        #expect(pdf.count > 10_000)
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }
}


@MainActor
struct RegressionTests {
    /// Day-only dates are Melbourne days and must display as that day on a Mac in any time zone.
    @Test func melbourneDayDisplaysSameDay() throws {
        let date = try #require(OpenDataClient.parseDate("2026-10-15"))
        #expect(MelbourneTime.day(date) == "15 Oct 2026")
        let instant = try #require(OpenDataClient.parseDate("2026-10-16T18:54:00+00:00"))
        #expect(MelbourneTime.time(instant) == "5:54 am Melbourne time")
    }

    /// Guide PDFs have no blank lines, so chunking must not fall back to one chunk per page.
    @Test func guidesSplitIntoPassages() async {
        let store = GuidesRetrievalStore()
        await store.loadAndIndex()
        #expect(store.loadError == nil)
        #expect(store.chunks.count > 20)
        #expect(store.chunks.allSatisfy { $0.text.count <= 700 })
        let top = store.topMatches(for: "When do I need to register for GST?", k: 6)
        #expect(top.contains { $0.text.contains("GST") })
    }
}

@MainActor
struct SpeechTests {
    @Test func answersAreCleanedForSpeech() {
        let answer = """
        The block scores **74/100** (Good):

        - **Foot traffic:** 61 × 40%. 919 people/hr, sensor 56 m away.
        - Business activity: 219 active · 2 km radius
        """
        let spoken = SpeechService.speakable(answer)
        #expect(!spoken.contains("*"))
        #expect(!spoken.contains("- "))
        #expect(spoken.contains("74 out of 100"))
        #expect(spoken.contains("61 times 40%"))
        #expect(spoken.contains("919 people per hour"))
        #expect(spoken.contains("56 metres"))
        #expect(spoken.contains("2 kilometres"))
        // Times and words must survive untouched.
        #expect(SpeechService.speakable("Opens 7am, box 5, 12 May") == "Opens 7am, box 5, 12 May")
    }

    @Test func australianVoiceAvailable() {
        #expect(AVSpeechSynthesisVoice(language: "en-AU") != nil)
    }

    /// Plays a short phrase through the speakers and waits for the synthesizer to finish.
    @Test(.timeLimit(.minutes(1))) func speaksAndFinishes() async throws {
        let speech = SpeechService.shared
        let id = UUID()
        speech.speak("iLoca speech check.", id: id)
        #expect(speech.speakingId == id)
        let deadline = Date().addingTimeInterval(20)
        while speech.speakingId != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(speech.speakingId == nil, "Speech never finished")

        // Toggling the same message stops it.
        speech.toggle("A longer sentence that would take a few seconds to read out loud.", id: id)
        #expect(speech.speakingId == id)
        try await Task.sleep(for: .milliseconds(400))
        #expect(speech.speakingId == id, "Still reading the long sentence before stop is pressed")
        speech.toggle("", id: id)
        #expect(speech.speakingId == nil)
    }
}
