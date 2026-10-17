import Foundation
import FoundationModels

// MARK: - Which model answers

enum AIProvider: Equatable {
    case claude
    case onDevice
    case unavailable(String)

    var displayName: String {
        switch self {
        case .claude: return "Claude (\(ClaudeClient.model))"
        case .onDevice: return "Apple on-device model"
        case .unavailable: return "Unavailable"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .onDevice: return "On-device AI"
        case .unavailable: return "AI unavailable"
        }
    }

    var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

// MARK: - API key
// Read only from the ANTHROPIC_API_KEY environment variable (set in the Xcode
// scheme: Product > Scheme > Edit Scheme > Run > Arguments). Nothing is stored
// by the app, and the per-user scheme is git-ignored.

enum APIKeyStore {
    static let environmentKey = "ANTHROPIC_API_KEY"

    static func load() -> String? {
        let key = ProcessInfo.processInfo.environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }
}

// MARK: - AI orchestrator
// Every AI feature (map advisor, guides, Info assistant, report narrative) goes
// through here, so they share one provider choice, one set of safety rules and
// one place to swap models.

@Observable
final class LocaAI {
    static let shared = LocaAI()

    private(set) var provider: AIProvider = .unavailable("Checking…")
    private(set) var hasAPIKey = false

    /// Rules appended to every system prompt.
    static let sharedRules = """

    General rules for every answer:
    - You are Loca, the assistant inside iLoca. You provide decision support, not financial, legal \
    or planning advice, and you never guarantee business success.
    - Ground every claim in the data supplied above. Never invent businesses, statistics, rents, \
    approvals or figures. If something isn't in the data, say so plainly and point to the closest \
    real signal you do have.
    - The data only covers the City of Melbourne municipality.
    - Location data does not confirm that a premises is zoned, permitted or suitable for a \
    particular use. Suggest checking with the City of Melbourne planning team when that matters.
    - Write in plain, conversational Australian English. Keep answers short (2-5 sentences) \
    unless the user asks for detail. Use no markdown headings, and bullets only for genuine lists.
    """

    init() { refresh() }

    func refresh() {
        hasAPIKey = APIKeyStore.load() != nil
        if hasAPIKey {
            provider = .claude
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            provider = .onDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            provider = .unavailable("Set ANTHROPIC_API_KEY to use Claude, or turn on Apple Intelligence in System Settings.")
        case .unavailable(.modelNotReady):
            provider = .unavailable("Set ANTHROPIC_API_KEY to use Claude. The on-device model is still downloading.")
        default:
            provider = .unavailable("Set ANTHROPIC_API_KEY to enable Loca.")
        }
    }

    /// - Parameter compactSystem: shorter grounding used by the on-device model, whose
    ///   context window is far smaller than Claude's.
    func stream(system: String, compactSystem: String? = nil, history: [ClaudeClient.Message], effort: String = "low",
                onModel: (@Sendable (String) -> Void)? = nil) -> AsyncThrowingStream<String, Error> {
        let fullSystem = system + Self.sharedRules
        switch provider {
        case .claude:
            guard let key = APIKeyStore.load() else {
                return AsyncThrowingStream { $0.finish(throwing: ClaudeError.missingAPIKey) }
            }
            return ClaudeClient(apiKey: key).stream(system: fullSystem, messages: history, effort: effort, onModel: onModel)

        case .onDevice:
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        // A fresh session per request keeps chats stateless (nothing is
                        // remembered between answers except the transcript we pass in).
                        let session = LanguageModelSession(instructions: (compactSystem ?? system) + Self.sharedRules)
                        // Only the last two exchanges fit alongside the grounding.
                        let transcript = history.dropLast().suffix(4).map { "\($0.role == "user" ? "User" : "Loca"): \($0.content)" }
                        let prompt = (transcript.isEmpty ? "" : "Conversation so far:\n\(transcript.joined(separator: "\n\n"))\n\n")
                            + (history.last?.content ?? "")
                        let response = try await session.respond(to: prompt)
                        continuation.yield(response.content)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }

        case .unavailable(let reason):
            return AsyncThrowingStream { $0.finish(throwing: ClaudeError.api(reason)) }
        }
    }

    /// One-shot completion, e.g. for the PDF report narrative.
    func complete(system: String, compactSystem: String? = nil, prompt: String, effort: String = "medium") async throws -> String {
        var text = ""
        for try await chunk in stream(system: system, compactSystem: compactSystem, history: [.init(role: "user", content: prompt)], effort: effort) {
            text += chunk
        }
        return text
    }
}
