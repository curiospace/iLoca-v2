//
//  GuidesAdvisorAI.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import Foundation

/// The AI for the Guides page. Unlike the Map advisor (grounded once per block),
/// this retrieves fresh excerpts from GuidesRetrievalStore for every question,
/// since a question might touch any combination of the four guides.
@Observable
final class GuidesAdvisorAI {
    let store = GuidesRetrievalStore()
    static let instructions = """
        You are Loca, a guide assistant helping a small business owner in Melbourne understand \
        official government guidance on starting, setting up, budgeting for and growing a business, \
        using four official guides (Plan, Setup, Budget, Grow).

        Rules:
        - Answer only from the guide text provided. Never invent fees, thresholds, deadlines or \
        requirements that aren't in it.
        - If the guides don't cover the question, say so and suggest which guide (Plan, Setup, \
        Budget or Grow) is most likely to help.
        - Mention which guide(s) the answer draws from, e.g. "From the Budget guide…".
        - Rules and fees change. For anything legal or regulatory, suggest confirming with the \
        relevant authority (e.g. City of Melbourne, ATO, Business Victoria).
        """

    let session = ChatSession(
        system: GuidesAdvisorAI.instructions,
        provenance: AnswerProvenance(sources: GuideBucket.allCases.map(\.documentTitle))
    )

    var messages: [ChatMessage] { session.messages }

    func prepare() async {
        if !store.isReady { await store.loadAndIndex() }
        // Claude gets all four guides in full (cached across questions); the on-device
        // model only has room for retrieved excerpts, sent with each question.
        let full = GuideBucket.allCases.compactMap { bucket in
            store.fullText[bucket].map { "=== \(bucket.title.uppercased()) GUIDE: \(bucket.documentTitle) ===\n\($0)" }
        }.joined(separator: "\n\n")
        session.updateGrounding(
            system: Self.instructions + "\n\nTHE FOUR GUIDES (full text):\n\n" + full,
            compactSystem: Self.instructions,
            provenance: AnswerProvenance(sources: GuideBucket.allCases.map(\.documentTitle))
        )
    }

    func ask(_ question: String) {
        if case .claude = LocaAI.shared.provider {
            session.ask(question, provenance: AnswerProvenance(
                sources: GuideBucket.allCases.map(\.documentTitle),
                notes: ["Loca read all four official guides in full and was told to answer only from them."]
            ))
            return
        }

        let matches = store.topMatches(for: question, k: 6)
        let excerpts = matches.isEmpty
            ? "No excerpts were retrieved. The guide library may still be indexing."
            : matches.map { "[\($0.bucket.title) guide]\n\($0.text)" }.joined(separator: "\n\n---\n\n")
        let prompt = """
        Relevant guide excerpts:
        \(excerpts)

        Question: \(question)
        """
        let guides = Array(Set(matches.map(\.bucket))).sorted { $0.rawValue < $1.rawValue }
        let provenance = AnswerProvenance(
            sources: guides.isEmpty ? ["No guide excerpts found"] : guides.map(\.documentTitle),
            notes: [
                "Found the \(matches.count) most relevant passages across all four guides using on-device sentence embeddings (NLEmbedding).",
                "Loca was told to answer only from those passages."
            ]
        )
        session.ask(question, prompt: prompt, provenance: provenance)
    }
}
