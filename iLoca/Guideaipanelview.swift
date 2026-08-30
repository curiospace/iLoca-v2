//
//  GuidesAIPanelView.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// The Guides page's persistent right-side AI panel. Same visual language as
/// AIPanelView (used on Home/Map), but always visible rather than toggled by
/// the floating mascot button, and grounded across all four guides.
struct GuidesAIPanelView: View {
    @Bindable var ai: GuidesAdvisorAI

    @State private var draftText: String = ""

    private let suggestedQuestions = [
        "What do I need to register before I open?",
        "How do I work out my break-even price?",
        "What licences does a Melbourne café need?",
        "When do I need to register for GST?",
        "How should I plan my cash flow?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))

            if ai.messages.isEmpty {
                emptyState
            } else {
                chatScrollView
            }

            Divider().overlay(Color.white.opacity(0.1))
            inputBar
        }
        .background(AppColor.navyBackground.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(AppColor.intelligenceGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("On-Device AI")
                    .font(AppFont.nav(14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Reads across all four guides")
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(AppColor.intelligenceGradient)

            Text(ai.isAvailable ? "Ask about any of the guides" : ai.availabilityStatus)
                .font(AppFont.nav(12))
                .foregroundStyle(AppColor.mutedGrey)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let loadError = ai.store.loadError {
                Text(loadError)
                    .font(AppFont.mono(10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if ai.isAvailable {
                VStack(spacing: 8) {
                    ForEach(suggestedQuestions, id: \.self) { question in
                        Button {
                            draftText = question
                            send()
                        } label: {
                            Text(question)
                                .font(AppFont.nav(12))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            Spacer()
        }
    }

    // MARK: - Chat transcript

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ai.messages) { message in
                        messageBubble(message)
                    }
                    if ai.isThinking {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Reading guides...")
                                .font(AppFont.nav(11))
                                .foregroundStyle(AppColor.mutedGrey)
                        }
                        .id("thinking")
                    }
                }
                .padding()
            }
            .onChange(of: ai.messages.count) {
                if let last = ai.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 30) }
            Text(message.text)
                .font(AppFont.nav(13))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(10)
                .background(message.isUser ? AppColor.tealAccent.opacity(0.85) : Color.white.opacity(0.08))
                .foregroundStyle(message.isUser ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !message.isUser { Spacer(minLength: 30) }
        }
        .id(message.id)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack {
            TextField("Ask about starting, setup, budget or growth...", text: $draftText)
                .textFieldStyle(.plain)
                .font(AppFont.nav(13))
                .foregroundStyle(.white)
                .padding(10)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { send() }
                .disabled(!ai.isAvailable)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.tealAccent)
            }
            .buttonStyle(.plain)
            .disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty || !ai.isAvailable)
        }
        .padding()
    }

    private func send() {
        let question = draftText.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
        draftText = ""
        Task { await ai.ask(question) }
    }
}