import SwiftUI

// MARK: - Shared chat UI used by the Map, Guides and Info assistants.

/// Header row: title, provider subtitle, and a Clear button (ephemeral chats).
struct ChatHeader: View {
    let title: String
    let subtitle: String
    var canClear: Bool = false
    var onClear: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var ai = LocaAI.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(AppColor.intelligenceGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.nav(14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
                    .lineLimit(1)
            }
            Spacer()
            if canClear, let onClear {
                Button(action: onClear) {
                    Label("Clear", systemImage: "trash")
                        .font(AppFont.nav(11, weight: .semibold))
                        .foregroundStyle(AppColor.mutedGrey)
                }
                .buttonStyle(.plain)
                .help("Clear this conversation. Chats are never saved.")
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColor.mutedGrey)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }
}

/// The AI disclosure strip shown above every chat.
struct AIDisclosureBanner: View {
    @State private var ai = LocaAI.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(AppColor.mutedGrey)
            Text("AI-generated answers from \(ai.provider.shortName). Decision support, not professional advice. Chats aren't saved.")
                .font(AppFont.nav(10))
                .foregroundStyle(AppColor.mutedGrey)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.textPrimary.opacity(0.03))
    }
}

/// Transcript with an empty state of suggested questions.
struct ChatTranscript: View {
    let session: ChatSession
    let emptyTitle: String
    let suggestions: [String]
    let onAsk: (String) -> Void

    @State private var ai = LocaAI.shared

    var body: some View {
        if session.messages.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(session.messages.enumerated()), id: \.element.id) { index, message in
                            ChatBubble(
                                message: message,
                                question: index > 0 ? session.messages[index - 1].text : nil
                            )
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .onChange(of: session.messages.last?.text) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColor.intelligenceGradient)
                    .padding(.top, 18)
                Text(ai.provider.isAvailable ? emptyTitle : (ai.provider.unavailableReason ?? "AI unavailable"))
                    .font(AppFont.nav(12))
                    .foregroundStyle(AppColor.mutedGrey)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if ai.provider.isAvailable {
                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { question in
                            Button { onAsk(question) } label: {
                                Text(question)
                                    .font(AppFont.nav(12))
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(AppColor.textPrimary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

/// One message. Assistant messages carry the AI label, a read-aloud button,
/// a report flag and an expandable "How Loca decided" section.
struct ChatBubble: View {
    let message: ChatMessage
    /// The user question this message answers (for issue reports).
    var question: String? = nil

    @State private var speech = SpeechService.shared
    @State private var showDecision = false
    @Environment(\.reportIssue) private var reportIssue

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 30) }
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if message.text.isEmpty && message.isStreaming {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
                        }
                    } else {
                        Text(Self.render(message.text))
                            .font(AppFont.nav(13))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(background)
                .foregroundStyle(message.isUser ? AppColor.onAccent : AppColor.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if !message.isUser && !message.isStreaming {
                    footer
                    if showDecision, let provenance = message.provenance {
                        decisionPanel(provenance)
                    }
                }
            }
            .frame(maxWidth: 300, alignment: message.isUser ? .trailing : .leading)
            if !message.isUser { Spacer(minLength: 30) }
        }
    }

    /// Inline markdown (bold, italics, links) while keeping line breaks.
    static func render(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private var background: Color {
        if message.isUser { return AppColor.tealAccent.opacity(0.85) }
        return message.isError ? AppColor.scorePoor.opacity(0.18) : AppColor.textPrimary.opacity(0.08)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("AI · \(message.provider ?? "Loca")")
                .font(AppFont.mono(9, weight: .semibold))
                .foregroundStyle(AppColor.mutedGrey)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(AppColor.mutedGrey.opacity(0.4), lineWidth: 1))

            if let level = message.provenance?.confidence {
                Label(level.rawValue, systemImage: level.icon)
                    .font(AppFont.nav(10, weight: .semibold))
                    .foregroundStyle(level.color)
                    .help("Data confidence for this answer")
            }

            Spacer(minLength: 0)

            if !message.isError {
                iconButton(speech.speakingId == message.id ? "stop.circle.fill" : "speaker.wave.2.fill",
                           help: speech.speakingId == message.id ? "Stop reading" : "Read aloud") {
                    speech.toggle(message.text, id: message.id)
                }
            }
            if message.provenance != nil {
                iconButton(showDecision ? "chevron.up.circle.fill" : "questionmark.circle",
                           help: "How Loca decided") {
                    withAnimation(.easeInOut(duration: 0.15)) { showDecision.toggle() }
                }
            }
            iconButton("flag", help: "Report an issue with this answer") {
                reportIssue(IssueContext(
                    confidence: message.provenance?.confidence?.rawValue,
                    flaggedAnswer: message.text,
                    flaggedQuestion: question,
                    provider: message.provider
                ))
            }
        }
        .padding(.horizontal, 2)
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundStyle(AppColor.mutedGrey)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func decisionPanel(_ p: AnswerProvenance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW LOCA DECIDED")
                .font(AppFont.mono(9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(AppColor.tealAccent)
            if let note = p.confidenceNote, let level = p.confidence {
                Text("Confidence \(level.rawValue): \(note)")
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
            }
            ForEach(p.notes, id: \.self) { note in
                Text("• \(note)").font(AppFont.nav(11)).foregroundStyle(AppColor.textPrimary.opacity(0.8))
            }
            Text("Sources: \(p.sources.joined(separator: "; "))")
                .font(AppFont.nav(10))
                .foregroundStyle(AppColor.mutedGrey)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
    }
}

/// Text field + send button.
struct ChatInputBar: View {
    let placeholder: String
    let isBusy: Bool
    let onSend: (String) -> Void

    @State private var draft = ""
    @State private var ai = LocaAI.shared

    var body: some View {
        HStack {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(AppFont.nav(13))
                .foregroundStyle(AppColor.textPrimary)
                .padding(10)
                .background(AppColor.textPrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit(send)
                .disabled(!ai.provider.isAvailable)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.tealAccent)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
        }
        .padding(12)
    }

    private var canSend: Bool {
        ai.provider.isAvailable && !isBusy && !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespaces)
        guard canSend else { return }
        draft = ""
        onSend(question)
    }
}

/// The full panel: header, disclosure, transcript, input.
struct LocaChatPanel: View {
    let title: String
    let subtitle: String
    let session: ChatSession
    let emptyTitle: String
    let suggestions: [String]
    let placeholder: String
    var onClose: (() -> Void)? = nil
    let onAsk: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(title: title, subtitle: subtitle, canClear: !session.messages.isEmpty,
                       onClear: { session.clear() }, onClose: onClose)
            AIDisclosureBanner()
            Divider().overlay(AppColor.textPrimary.opacity(0.08))
            ChatTranscript(session: session, emptyTitle: emptyTitle, suggestions: suggestions, onAsk: onAsk)
                .frame(maxHeight: .infinity)
            Divider().overlay(AppColor.textPrimary.opacity(0.08))
            ChatInputBar(placeholder: placeholder, isBusy: session.isThinking, onSend: onAsk)
        }
        .background(AppColor.navyBackground.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.textPrimary.opacity(0.08), lineWidth: 1))
        .shadow(radius: 12)
    }
}
