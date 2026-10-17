import Foundation
import Testing
@testable import iLoca

/// Asks Claude real questions and checks the answers against ground truth computed
/// from the same live data. Also flags any number in an answer that doesn't appear
/// in the grounding (a likely hallucination). Every Q&A is written to
/// iloca_claude_accuracy.txt in the test's temporary directory for manual review.
/// Skipped unless ANTHROPIC_API_KEY is set (it costs real API calls).
@MainActor
@Suite(.serialized)
struct ClaudeAccuracyTests {

    struct Check {
        let label: String
        let passed: Bool
    }

    final class Log {
        var text = ""
        func add(_ s: String) { text += s + "\n" }
        func save() {
            try? text.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("iloca_claude_accuracy.txt"),
                            atomically: true, encoding: .utf8)
        }
    }
    static let log = Log()

    // MARK: Helpers

    private func ask(_ session: ChatSession, _ question: String, send: () -> Void) async throws -> ChatMessage {
        send()
        let deadline = Date().addingTimeInterval(120)
        while session.isThinking && Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
        let reply = try #require(session.messages.last)
        #expect(!reply.isUser)
        #expect(!reply.isError, "Error reply: \(reply.text)")
        return reply
    }

    /// Numbers in the answer (commas stripped), e.g. "1,234" -> "1234", "26.5%" -> "26.5".
    private func numbers(in text: String) -> [String] {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        return regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)).compactMap {
            Range($0.range, in: cleaned).map { String(cleaned[$0]) }
        }
    }

    /// Numbers in the answer that appear nowhere in the grounding text.
    private func ungrounded(_ answer: String, grounding: String) -> [String] {
        let source = grounding.replacingOccurrences(of: ",", with: "")
        let sourceNumbers = Set(numbers(in: source))
        return numbers(in: answer).filter { n in
            if sourceNumbers.contains(n) { return false }
            // Allow rounding of a grounded decimal (e.g. 26.5 -> 27 or 26) and small ordinals.
            if let v = Double(n), v <= 10 { return false }
            if let v = Double(n), sourceNumbers.contains(where: { Double($0).map { abs($0 - v) < 1 } ?? false }) { return false }
            return true
        }
    }

    private func contains(_ text: String, _ needle: String) -> Bool {
        text.replacingOccurrences(of: ",", with: "").localizedCaseInsensitiveContains(needle)
    }

    private func record(_ id: String, _ question: String, _ reply: ChatMessage, truth: String, checks: [Check], grounding: String) {
        let flagged = ungrounded(reply.text, grounding: grounding)
        let log = Self.log
        log.add("=== \(id)")
        log.add("Q: \(question)")
        log.add("MODEL: \(reply.provider ?? "-")")
        log.add("A: \(reply.text)")
        log.add("TRUTH: \(truth)")
        for c in checks { log.add("  [\(c.passed ? "PASS" : "FAIL")] \(c.label)") }
        log.add("  ungrounded numbers: \(flagged.isEmpty ? "none" : flagged.joined(separator: ", "))")
        log.add("")
        log.save()
        for c in checks { #expect(c.passed, "\(id): \(c.label)\nAnswer: \(reply.text)") }
    }

    private func loadedStore() async throws -> CityDataStore {
        let store = CityDataStore()
        await store.load()
        await store.refreshOnStreetIfStale()
        store.filters.businessCategory = .cafe
        store.filters.timesOfDay = [.lunch]
        store.selectedBlockId = 25
        await store.loadPremises(for: 25)
        _ = try #require(store.selectedBlock)
        return store
    }

    // MARK: Tests

    @Test(.timeLimit(.minutes(10))) func mapAdvisorAnswersMatchData() async throws {
        let ai = LocaAI.shared
        ai.refresh()
        guard case .claude = ai.provider else { return }
        Self.log.add("Requested model: \(ClaudeClient.model)\n")

        let store = try await loadedStore()
        let block = store.selectedBlock!
        let metrics = try #require(store.metrics(for: block))
        let confidence = store.confidence(for: block)
        let premises = try #require(store.premisesByBlock[25])
        let fnbNames = premises.filter { $0.category == .cafe }.map(\.name)
        let parking = store.parking(for: block)
        let advisor = LocationAdvisorAI()
        advisor.reground(store: store)
        let grounding = advisor.session.system

        func run(_ id: String, _ q: String) async throws -> ChatMessage {
            advisor.session.clear()
            return try await ask(advisor.session, q) { advisor.ask(q, store: store) }
        }

        // 1. Score + tier
        var q = "What is this block's Opportunity Score and tier? Answer in one sentence."
        var r = try await run("score", q)
        record("1 score", q, r, truth: "\(metrics.score.value) \(metrics.score.tier.rawValue)", checks: [
            Check(label: "mentions score \(metrics.score.value)", passed: contains(r.text, "\(metrics.score.value)")),
            Check(label: "mentions tier \(metrics.score.tier.rawValue)", passed: contains(r.text, metrics.score.tier.rawValue)),
            Check(label: "served by \(ClaudeClient.model)", passed: r.provider?.hasPrefix(ClaudeClient.model) == true)
        ], grounding: grounding)

        // 2. Score explanation (factor values)
        q = "Why does this block have that score? Give each factor's value."
        r = try await run("why", q)
        let parts = metrics.score.components.compactMap { c in c.value.map { (c.kind.rawValue, Int($0.rounded())) } }
        record("2 why", q, r, truth: parts.map { "\($0.0) \($0.1)" }.joined(separator: ", "),
               checks: parts.map { Check(label: "mentions \($0.0) value \($0.1)", passed: contains(r.text, "\($0.1)")) },
               grounding: grounding)

        // 3. Vacancy
        q = "How many premises are vacant here, and what is the vacancy rate?"
        r = try await run("vacancy", q)
        let rate = String(format: "%.1f", block.vacancyRatePct)
        record("3 vacancy", q, r, truth: "\(block.vacantPremises) of \(block.totalPremises), \(rate)%", checks: [
            Check(label: "mentions \(block.vacantPremises) vacant", passed: contains(r.text, "\(block.vacantPremises)")),
            Check(label: "mentions rate \(rate) (or rounded)", passed: contains(r.text, rate) || contains(r.text, "\(Int(block.vacancyRatePct.rounded()))%"))
        ], grounding: grounding)

        // 4. Named FnB competitors must be real
        q = "Name three cafés or restaurants in this block."
        r = try await run("names", q)
        let named = fnbNames.filter { contains(r.text, $0) }
        record("4 names", q, r, truth: "\(fnbNames.count) FnB businesses, e.g. \(fnbNames.prefix(5).joined(separator: "; "))", checks: [
            Check(label: "at least 3 real FnB names from dataset (found \(named.count): \(named.prefix(5).joined(separator: "; ")))", passed: named.count >= 3)
        ], grounding: grounding)

        // 5. Foot traffic in selected window
        q = "How busy is it at lunchtime? Give the people-per-hour figure."
        r = try await run("footfall", q)
        let ff = Int((metrics.footfall ?? 0).rounded())
        record("5 footfall", q, r, truth: "\(ff) people/hr (lunch, all week)", checks: [
            Check(label: "mentions \(ff) people/hr", passed: contains(r.text, "\(ff)"))
        ], grounding: grounding)

        // 6. Confidence
        q = "How confident is this assessment?"
        r = try await run("confidence", q)
        record("6 confidence", q, r, truth: "\(confidence.level.rawValue) (\(confidence.points)/100)", checks: [
            Check(label: "mentions level \(confidence.level.rawValue)", passed: contains(r.text, confidence.level.rawValue))
        ], grounding: grounding)

        // 7. Parking
        q = "How many on-street parking bays are free nearby right now, and how many public car parks are within the radius?"
        r = try await run("parking", q)
        record("7 parking", q, r, truth: "\(parking.freeBays) of \(parking.bayCount) bays free; \(parking.carParks.count) car parks", checks: [
            Check(label: "mentions \(parking.freeBays) free bays", passed: contains(r.text, "\(parking.freeBays)")),
            Check(label: "mentions \(parking.carParks.count) car parks", passed: contains(r.text, "\(parking.carParks.count)"))
        ], grounding: grounding)

        // 8. Missing data: rent must not be invented
        q = "What's the monthly rent for a shop in this block?"
        r = try await run("rent", q)
        let dollar = r.text.contains("$")
        record("8 rent (not in data)", q, r, truth: "Not available in iLoca's data", checks: [
            Check(label: "no dollar figure invented", passed: !dollar),
            Check(label: "says it's not available", passed: ["not available", "don't have", "do not have", "isn't", "not in", "no rent", "doesn't include", "not include", "can't", "cannot"].contains { contains(r.text, $0) })
        ], grounding: grounding)

        // 9. Fake business must not be confirmed
        q = "Is 'Zebra Moon Espresso' in this block?"
        r = try await run("fake", q)
        record("9 fake business", q, r, truth: "Not in the dataset", checks: [
            Check(label: "does not confirm the fake business", passed: ["not", "no ", "isn't", "doesn't", "couldn't", "can't"].contains { contains(r.text, $0) })
        ], grounding: grounding)
    }

    @Test(.timeLimit(.minutes(5))) func cityOverviewTopBlock() async throws {
        let ai = LocaAI.shared
        ai.refresh()
        guard case .claude = ai.provider else { return }
        let store = try await loadedStore()
        store.selectedBlockId = nil
        let advisor = LocationAdvisorAI()
        advisor.reground(store: store)
        let top = try #require(store.visibleBlocks.compactMap { b in store.metrics(for: b).map { (b, $0.score.value) } }.max { $0.1 < $1.1 })
        let q = "Which single block has the highest Opportunity Score right now, and what is its score?"
        let r = try await ask(advisor.session, q) { advisor.ask(q, store: store) }
        record("10 city top block", q, r, truth: "Block \(top.0.blockId), score \(top.1)", checks: [
            Check(label: "names block \(top.0.blockId)", passed: contains(r.text, "\(top.0.blockId)")),
            Check(label: "gives score \(top.1)", passed: contains(r.text, "\(top.1)"))
        ], grounding: advisor.session.system)
    }

    @Test(.timeLimit(.minutes(5))) func infoAssistantExplainsMethod() async throws {
        let ai = LocaAI.shared
        ai.refresh()
        guard case .claude = ai.provider else { return }
        let store = try await loadedStore()
        let info = InfoAdvisorAI()
        info.ground(store: store)
        let q = "What weights does the Opportunity Score give to each factor?"
        let r = try await ask(info.session, q) { info.session.ask(q) }
        record("11 info weights", q, r, truth: "Foot traffic 40%, occupied shopfronts 40%, business activity 20%", checks: [
            Check(label: "mentions 40%", passed: contains(r.text, "40")),
            Check(label: "mentions 20%", passed: contains(r.text, "20"))
        ], grounding: info.session.system)
    }

    @Test(.timeLimit(.minutes(5))) func guideAnswerUsesExcerpts() async throws {
        let ai = LocaAI.shared
        ai.refresh()
        guard case .claude = ai.provider else { return }
        let guides = GuidesAdvisorAI()
        await guides.prepare()
        #expect(guides.store.chunks.count > 20)
        let q = "When do I need to register for GST?"
        let r = try await ask(guides.session, q) { guides.ask(q) }
        let source = guides.session.system
        let flagged = ungrounded(r.text, grounding: source)
        let threshold = source.contains("75,000") || source.contains("75 000")
        record("12 guide GST", q, r, truth: threshold ? "Guides state the $75,000 turnover threshold" : "Guides don't state a threshold", checks: [
            Check(label: "cites a guide", passed: contains(r.text, "guide")),
            Check(label: "states $75,000 threshold from the guide", passed: !threshold || contains(r.text, "75000") || contains(r.text, "75k")),
            Check(label: "every number appears in the guides (\(flagged))", passed: flagged.isEmpty)
        ], grounding: source)
        let prompt = source
        // Save the excerpts for manual review of the guide answer.
        Self.log.add("--- excerpts given for Q12 ---\n\(prompt)\n")
        Self.log.save()
    }
}
