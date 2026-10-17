import AVFoundation
import Observation

/// Reads AI answers aloud ("Ask and listen"), on-device via AVSpeechSynthesizer.
@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    /// The message currently being read, so its speaker button can show "stop".
    private(set) var speakingId: UUID?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// The utterance being read, so callbacks from an earlier (stopped or finished)
    /// utterance can't clear the state of the current one.
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String, id: UUID) {
        if speakingId == id {
            stop()
        } else {
            speak(text, id: id)
        }
    }

    func speak(_ text: String, id: UUID) {
        stop()
        let utterance = AVSpeechUtterance(string: Self.speakable(text))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingId = id
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// Turns an answer into text that sounds natural read aloud: drops markdown
    /// symbols and expands units the voice would otherwise spell out.
    static func speakable(_ text: String) -> String {
        var s = text
        let replacements: [(String, String)] = [
            (#"\*\*|__|`"#, ""),                            // bold, code
            (#"(?m)^#+\s*"#, ""),                            // headings
            (#"(?m)^\s*[-•*]\s+"#, ""),                      // bullet markers
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),               // [link](url) -> link
            (#"\s*/\s*hr\b"#, " per hour"),                  // 919/hr, people/hr
            (#"people/hour"#, "people per hour"),
            (#"(\d+)\s*/\s*(\d+)"#, "$1 out of $2"),           // 74/100
            (#"(\d)\s*km\b"#, "$1 kilometres"),
            (#"(\d)\s*m\b"#, "$1 metres"),
            (#"(?<=\d)\s*[×x]\s*(?=\d)"#, " times "),          // 61 × 40%
            (#"\s·\s"#, ", "),
            (#"[–—]"#, ", "),
            (#"\n{2,}"#, ". "),
        ]
        for (pattern, template) in replacements {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        // Single leftover asterisks (italics) and doubled punctuation.
        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: #"\.\s*\."#, with: ".", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() {
        currentUtterance = nil
        speakingId = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(finished) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelled = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(cancelled) }
    }

    private func utteranceEnded(_ utterance: ObjectIdentifier) {
        guard let current = currentUtterance, ObjectIdentifier(current) == utterance else { return }
        currentUtterance = nil
        speakingId = nil
    }
}
