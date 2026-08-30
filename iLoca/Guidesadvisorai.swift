//
//  GuidesAdvisorAI.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import Foundation
import FoundationModels

// Note: ChatMessage is already defined in LocationAdvisorAI.swift and is
// reused here — do not redeclare it in this file.

/// The AI "brain" for the Guides page. Unlike LocationAdvisorAI (which primes
/// one session with a fixed block's data), this retrieves fresh excerpts from
/// GuidesRetrievalStore for every question, since a question might touch any
/// combination of the four guides.
@Observable
class GuidesAdvisorAI {
    var messages: [ChatMessage] = []
    var isThinking: Bool = false

    var isAvailable: Bool = false
    var availabilityStatus: String = "Checking..."

    let store = GuidesRetrievalStore()
    private var session: LanguageModelSession?

    func checkAvailability() {
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
            availabilityStatus = "Ready"
        case .unavailable(.deviceNotEligible):
            isAvailable = false
            availabilityStatus = "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            isAvailable = false
            availabilityStatus = "Turn on Apple Intelligence in System Settings to use this."
        case .unavailable(.modelNotReady):
            isAvailable = false
            availabilityStatus = "The on-device model is still downloading. Try again shortly."
        case .unavailable(let other):
            isAvailable = false
            availabilityStatus = "Unavailable: \(other)"
        @unknown default:
            isAvailable = false
            availabilityStatus = "Unavailable for an unknown reason."
        }
    }

    /// Loads/indexes the PDFs (once) and starts the session. Call from the
    /// Guides page's .task so it's ready before the user asks anything.
    func prepare() async {
        if !store.isReady {
            await store.loadAndIndex()
        }
        if session == nil {
            startSession()
        }
    }

    private func startSession() {
        let instructions = """
        You are a guide assistant helping a small business owner in Melbourne understand \
        official government guidance on starting, setting up, budgeting for and growing a \
        business. Before each question you will be given real excerpts drawn from four \
        official guides — Plan, Setup, Budget and Grow — retrieved because they're relevant \
        to what was asked. Excerpts may come from one guide or span several.

        Rules you must follow:
        - Answer only using the excerpts provided with each question. Never invent facts, \
        figures, thresholds, fees or requirements that aren't present in the excerpts.
        - If the excerpts don't cover what was asked, say so plainly and suggest which guide \
        (Plan, Setup, Budget or Grow) is most likely to help, rather than guessing.
        - When it's useful, mention which guide(s) the answer draws from, e.g. "From the \
        Budget guide...".
        - Vary your phrasing naturally — don't repeat the same sentence structure for every \
        answer.
        - Keep answers concise: 2-5 sentences, plain conversational language, no bullet lists \
        unless the question specifically calls for a checklist.
        """
        session = LanguageModelSession(instructions: instructions)
    }

    func ask(_ question: String) async {
        if session == nil {
            await prepare()
        }
        guard let session else {
            messages.append(ChatMessage(isUser: true, text: question))
            messages.append(ChatMessage(isUser: false, text: "The guide library hasn't finished loading yet — try again in a moment."))
            return
        }

        messages.append(ChatMessage(isUser: true, text: question))
        isThinking = true
        defer { isThinking = false }

        let matches = store.topMatches(for: question, k: 6)
        let excerptText: String
        if matches.isEmpty {
            excerptText = "No excerpts were retrieved — the guide library may still be indexing, or nothing relevant was found."
        } else {
            excerptText = matches
                .map { "[\($0.bucket.title) guide]\n\($0.text)" }
                .joined(separator: "\n\n---\n\n")
        }

        let prompt = """
        Relevant guide excerpts:
        \(excerptText)

        Question: \(question)
        """

        do {
            let response = try await session.respond(to: prompt)
            messages.append(ChatMessage(isUser: false, text: response.content))
        } catch {
            messages.append(ChatMessage(isUser: false, text: "Sorry, something went wrong answering that: \(error.localizedDescription)"))
        }
    }
}