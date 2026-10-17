//
//  GuidesAIPanelView.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// The Guides page's persistent right-side AI panel, grounded across all four guides.
struct GuidesAIPanelView: View {
    let ai: GuidesAdvisorAI

    private let suggestedQuestions = [
        "What do I need to register before I open?",
        "How do I work out my break-even price?",
        "What licences does a Melbourne café need?",
        "When do I need to register for GST?",
        "How should I plan my cash flow?"
    ]

    var body: some View {
        VStack(spacing: 8) {
            LocaChatPanel(
                title: "Loca · Guide Assistant",
                subtitle: ai.store.isReady ? "Reads across all four guides" : "Indexing guides…",
                session: ai.session,
                emptyTitle: "Ask about any of the guides",
                suggestions: suggestedQuestions,
                placeholder: "Ask about starting, setup, budget or growth…",
                onAsk: { ai.ask($0) }
            )
            if let loadError = ai.store.loadError {
                Text(loadError)
                    .font(AppFont.mono(10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
