import Foundation
import FoundationModels

// MARK: - One message in the chat (either from you, or from the AI)

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

// MARK: - The AI "brain" for the Location Advisor panel.
// This talks to Apple's on-device Foundation Models framework — no internet needed,
// nothing leaves the Mac. That's the whole point of this hackathon track.

@Observable
class LocationAdvisorAI {
    var messages: [ChatMessage] = []
    var isThinking: Bool = false

    // Whether the on-device model is usable right now on this Mac
    var availabilityStatus: String = "Checking..."
    var isAvailable: Bool = false

    private var session: LanguageModelSession?
    private var currentBlockId: Int?

    /// Call this once when the app launches, to check whether Apple Intelligence
    /// is turned on and the model is ready to use.
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

    /// Starts a fresh conversation grounded in a specific block's real data.
    /// Called every time the user selects a different block.
    func startNewSession(for context: BlockAIContext) {
        currentBlockId = context.blockId
        messages = []

        let instructions = """
        You are a location advisor helping someone decide whether a Melbourne CBD city block \
        is a good fit for a new small business. You are given REAL data about one specific \
        block: the actual named businesses there (where available), business counts by \
        category, the vacancy rate, and (if available) real pedestrian foot traffic patterns \
        by hour.

        Rules you must follow:
        - Only use the businesses and numbers given to you in the data below. Never invent a \
        business name, category, or statistic.
        - The 3D map the user sees also shows Apple Maps' own live business listings (shop \
        names/icons on the map itself). Those are NOT part of your data and you have no \
        information about them — if asked about a specific named business you don't recognize \
        from your data below, say plainly that it isn't part of your verified dataset, don't \
        guess, and suggest checking the map label directly instead.
        - You have no ability to calculate walking distance or "nearest" between businesses — \
        if asked which business is nearest/closest, say that distance calculation isn't \
        something you can do, and instead mention which relevant businesses ARE in this block \
        from your data.
        - If asked about something else not included in the data (like exact rent prices, \
        revenue, or ROI), clearly say that specific figure isn't available, and instead offer \
        the closest real signal you DO have (e.g. vacancy rate, competitor density, or foot \
        traffic).
        - Vary your phrasing naturally — never repeat the exact same sentence for different \
        questions. Address what was actually asked each time.
        - Keep answers short: 2-4 sentences, plain conversational language, no bullet lists \
        unless truly helpful.
        - Be specific and use the actual numbers/names from the data, not vague statements.
        """

        session = LanguageModelSession(instructions: instructions)
        primeSession(with: "Here is the data for the block we'll discuss:\n\(context.dataSummary)\n\nJust acknowledge you're ready — don't summarize yet.")
    }

    /// Starts a fresh conversation grounded in city-wide aggregate stats, for
    /// when no specific block is selected yet. Same honesty rules as the
    /// block-specific session — just a wider, shallower dataset underneath.
    func startGeneralSession(overview: String) {
        currentBlockId = nil
        messages = []

        let instructions = """
        You are a location advisor helping someone explore Melbourne CBD blocks to find a \
        good fit for a new small business. No specific block has been selected yet — you have \
        REAL city-wide summary data below (aggregated across all loaded blocks), not per-block \
        detail.

        Rules you must follow:
        - Only use the numbers given to you in the data below. Never invent statistics.
        - If asked about a specific block by number, or something too granular for city-wide \
        data (like exact rent, revenue, or ROI), say clearly that level of detail isn't \
        available in this general view, and suggest they select a block on the map for \
        block-level detail.
        - Keep answers short: 2-4 sentences, plain conversational language, no bullet lists \
        unless truly helpful.
        - Be specific and use the actual numbers from the data, not vague statements.
        """

        session = LanguageModelSession(instructions: instructions)
        primeSession(with: "Here is the city-wide data so far:\n\(overview)\n\nJust acknowledge you're ready — don't summarize yet.")
    }

    private func primeSession(with primerText: String) {
        Task {
            do {
                _ = try await session?.respond(to: primerText)
            } catch {
                print("⚠️ Failed to prime AI session: \(error)")
            }
        }
    }

    /// Sends a question to the AI and appends both the question and the answer to the chat.
    func ask(_ question: String) async {
        guard let session else {
            messages.append(ChatMessage(isUser: true, text: question))
            messages.append(ChatMessage(
                isUser: false,
                text: "The AI session hasn't started yet — this shouldn't normally happen. Try selecting a block or reopening this panel."
            ))
            return
        }
        messages.append(ChatMessage(isUser: true, text: question))
        isThinking = true
        defer { isThinking = false }

        do {
            let response = try await session.respond(to: question)
            messages.append(ChatMessage(isUser: false, text: response.content))
        } catch {
            messages.append(ChatMessage(isUser: false, text: "Sorry, something went wrong answering that: \(error.localizedDescription)"))
        }
    }
}

// MARK: - Builds the grounded data summary handed to the AI for a given block.
// This is the important bit: it turns your real JSON data into plain text the model can read,
// and it's honest about what's missing rather than letting the model guess.

struct BlockAIContext {
    let blockId: Int
    let dataSummary: String

    init(summary: BlockSummary, detail: BlockDetail?) {
        self.blockId = summary.blockId
        var lines: [String] = []

        lines.append("Block ID: \(summary.blockId), area: \(summary.clueSmallArea)")
        lines.append("Active businesses: \(summary.activeEstablishments)")
        lines.append("Vacant shopfronts: \(summary.vacantCount) (\(String(format: "%.1f", summary.vacancyRatePct))% vacancy rate)")

        if let peakHour = summary.avgPeakHourWeekday, let peakCount = summary.avgPeakCountWeekday {
            lines.append("Real pedestrian data available: weekday foot traffic peaks around \(peakHour):00 at roughly \(peakCount) people/hour.")
        } else {
            lines.append("No pedestrian sensor data is available for this specific block.")
        }

        if let detail {
            lines.append("\nFull industry breakdown (business count by type):")
            for (industry, count) in detail.industryBreakdown.sorted(by: { $0.value > $1.value }).prefix(15) {
                lines.append("- \(industry): \(count)")
            }

            // The actual named businesses — this is what lets the AI answer
            // "is there a cafe here" or "name a business" instead of only
            // knowing category counts.
            lines.append("\nActual named businesses in this block (real data, up to 40 shown):")
            for biz in detail.businesses.prefix(40) {
                lines.append("- \(biz.name) (\(biz.industryAnzsic4)) — \(biz.address)")
            }
            if detail.businesses.count > 40 {
                lines.append("...and \(detail.businesses.count - 40) more businesses not listed here individually, but counted in the industry breakdown above.")
            }
        } else {
            lines.append("\nTop industries in this block:")
            for (industry, count) in summary.topIndustries.sorted(by: { $0.value > $1.value }) {
                lines.append("- \(industry): \(count)")
            }
            lines.append("\nNo individual business names are available for this block — only category-level counts above.")
        }

        lines.append("\nNo walking-distance or 'nearest business' calculation is available — you cannot determine which business is physically closest to another point.")
        lines.append("\nAny business names/icons visible on the map itself that are NOT listed above are from Apple Maps' own live business data, not part of this dataset — you have no information about them.")

        lines.append("\nData NOT available for this block: exact commercial rent prices, revenue/ROI figures, off-street parking counts, floor space in square metres, residential dwelling counts. If asked about these, be honest they're not available rather than guessing.")

        self.dataSummary = lines.joined(separator: "\n")
    }
}
