//
//  ReportGenerator.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import Foundation

enum ReportGenerator {
    /// Generates the report's narrative with a fresh, dedicated request (separate
    /// from the chat), so the report stays consistent whatever was asked in chat.
    static func generateNarrative(blockContext: String, compactContext: String, filtersSummary: String) async -> (text: String, provider: String) {
        let ai = LocaAI.shared
        func system(_ context: String) -> String { """
        You are writing a short, formal location-analysis section for a printed report for a \
        business owner considering a City of Melbourne block. Use ONLY the data provided. Write \
        2-3 short paragraphs in a professional report tone: no greetings, no "I", no markdown. \
        Explain what drives the Opportunity Score using its factor breakdown, factor in the user's \
        filters (business type, time window, competition), and state the confidence level and its \
        main limitation. If something relevant isn't in the data, say so plainly.

        \(context)
        """ }
        do {
            let text = try await ai.complete(
                system: system(blockContext),
                compactSystem: system(compactContext),
                prompt: "Filters applied by the user when this report was generated:\n\(filtersSummary)\n\nWrite the analysis now.",
                effort: "medium"
            )
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), ai.provider.displayName)
        } catch {
            return ("AI analysis wasn't available when this report was generated (\(error.localizedDescription)). The figures below are still accurate and drawn from City of Melbourne open data.", "None")
        }
    }
}
