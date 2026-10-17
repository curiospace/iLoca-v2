import Foundation

/// What an AI answer was based on, shown under it as "How Loca decided".
struct AnswerProvenance {
    var sources: [String]
    var confidence: ConfidenceLevel? = nil
    var confidenceNote: String? = nil
    var notes: [String] = []
}

/// One message in a chat (from the user, or from Loca).
struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
    /// What was actually sent to the model for a user turn, when it differs
    /// from what's displayed (e.g. with retrieved guide excerpts attached).
    var promptText: String? = nil
    var isStreaming = false
    var isError = false
    var provider: String? = nil
    var provenance: AnswerProvenance? = nil
}

/// An ephemeral conversation: held in memory only, never written to disk,
/// and discarded when cleared, re-grounded (for example on a new block
/// selection) or when the app quits.
@Observable
final class ChatSession {
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false

    /// Grounding instructions + data for the model.
    private(set) var system: String
    /// Shorter grounding for the on-device model's small context window.
    private(set) var compactSystem: String?
    private(set) var provenance: AnswerProvenance

    @ObservationIgnored private var currentTask: Task<Void, Never>?

    init(system: String = "", provenance: AnswerProvenance = .init(sources: [])) {
        self.system = system
        self.provenance = provenance
    }

    /// Re-grounds the session. Clears the transcript, since earlier answers
    /// were about different data.
    func reset(system: String, compactSystem: String? = nil, provenance: AnswerProvenance) {
        clear()
        self.system = system
        self.compactSystem = compactSystem
        self.provenance = provenance
    }

    /// Updates grounding without clearing (e.g. data refreshed, same subject).
    func updateGrounding(system: String, compactSystem: String? = nil, provenance: AnswerProvenance) {
        self.system = system
        self.compactSystem = compactSystem
        self.provenance = provenance
    }

    func clear() {
        currentTask?.cancel()
        currentTask = nil
        SpeechService.shared.stop()
        messages = []
        isThinking = false
    }

    /// Sends a question. `prompt` overrides what's sent (the display text stays `question`);
    /// `provenance` overrides the session-level provenance for this answer.
    func ask(_ question: String, prompt: String? = nil, provenance override: AnswerProvenance? = nil) {
        let history = apiHistory() + [.init(role: "user", content: prompt ?? question)]
        messages.append(ChatMessage(isUser: true, text: question, promptText: prompt))

        let ai = LocaAI.shared
        let reply = ChatMessage(isUser: false, text: "", isStreaming: true,
                                provider: ai.provider.shortName, provenance: override ?? provenance)
        messages.append(reply)
        let replyId = reply.id
        isThinking = true

        let system = self.system, compactSystem = self.compactSystem
        currentTask = Task { [weak self] in
            do {
                let onModel: @Sendable (String) -> Void = { model in
                    Task { @MainActor in self?.updateReply(replyId) { $0.provider = model } }
                }
                for try await chunk in ai.stream(system: system, compactSystem: compactSystem, history: history, onModel: onModel) {
                    guard let self, !Task.isCancelled else { return }
                    self.updateReply(replyId) { $0.text += chunk }
                }
                self?.updateReply(replyId) {
                    $0.isStreaming = false
                    if $0.text.isEmpty { $0.text = "Loca didn't return an answer. Try asking again." ; $0.isError = true }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.updateReply(replyId) {
                    $0.isStreaming = false
                    $0.isError = true
                    $0.text = $0.text.isEmpty ? error.localizedDescription : $0.text + "\n\n(\(error.localizedDescription))"
                }
            }
            self?.isThinking = false
        }
    }

    private func updateReply(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
    }

    /// Completed user/assistant pairs only; failed turns are left out so the
    /// model never sees its own error text as an answer.
    private func apiHistory() -> [ClaudeClient.Message] {
        var result: [ClaudeClient.Message] = []
        var i = 0
        while i + 1 < messages.count {
            let user = messages[i], reply = messages[i + 1]
            if user.isUser, !reply.isUser, !reply.isError, !reply.isStreaming {
                result.append(.init(role: "user", content: user.promptText ?? user.text))
                result.append(.init(role: "assistant", content: reply.text))
            }
            i += 2
        }
        return result
    }
}
