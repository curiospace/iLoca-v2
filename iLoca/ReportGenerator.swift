//
//  ReportGenerator.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import Foundation
import FoundationModels

enum ReportGenerator {
    /// Generates the report's short narrative analysis using a fresh,
    /// dedicated on-device session — separate from the block chat session, so
    /// the report's content stays consistent regardless of what's been asked
    /// in chat, and so report generation can't be derailed by prior chat turns.
    static func generateNarrative(dataSummary: String, filtersSummary: String) async -> String {
        let instructions = """
        You are writing a short, formal location-analysis section for a printed report, for a \
        business owner considering a Melbourne city block. Use ONLY the real data provided \
        below — never invent statistics, business names, or figures not present in the data. \
        Write 2-3 short paragraphs in a clear, professional report tone (not conversational \
        chat style, no greetings, no "I"). If a filter meaningfully narrows relevance (e.g. a \
        specific business type or footfall level), factor that into the analysis. If something \
        relevant isn't in the data, say so plainly rather than guessing.
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            Block data:
            \(dataSummary)

            Filters applied by the user when this report was generated:
            \(filtersSummary)

            Write the analysis now.
            """
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return "On-device AI analysis wasn't available when this report was generated (\(error.localizedDescription)). The statistics below are still accurate and drawn from real data."
        }
    }
}