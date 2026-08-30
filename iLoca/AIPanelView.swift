import SwiftUI

struct AIPanelView: View {
    @Bindable var ai: LocationAdvisorAI
    let blockLabel: String   // e.g. "Block 25 · Melbourne (CBD)"
    @Binding var isVisible: Bool

    @State private var draftText: String = ""

    // A handful of good starter questions, shown as tappable chips before the user has asked anything.
    private let suggestedQuestions = [
        "How is the foot traffic here?",
        "What are the main competitors nearby?",
        "Is this a good spot for a cafe?",
        "How does this compare to a quieter block?",
        "What's the vacancy rate telling us?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if ai.messages.isEmpty {
                emptyState
            } else {
                chatScrollView
            }

            Divider()
            inputBar
        }
        .frame(width: 400, height: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(AppColor.intelligenceGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("On-Device AI").font(.headline)
                Text("Location Advisor · \(blockLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Empty state (before any question is asked)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.intelligenceGradient)
            Text("Ask about this location")
                .font(.headline)
            Text(ai.isAvailable ? "AI-powered insights, entirely on your Mac" : ai.availabilityStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if ai.isAvailable {
                VStack(spacing: 8) {
                    ForEach(suggestedQuestions, id: \.self) { question in
                        Button {
                            draftText = question
                            send()
                        } label: {
                            Text(question)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.gray.opacity(0.12))
                                .cornerRadius(8)
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
                            Text("Thinking...").font(.caption).foregroundStyle(.secondary)
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
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true) // forces wrapping instead of overflowing
                .frame(maxWidth: 280, alignment: .leading)
                .padding(10)
                .background(message.isUser ? Color.accentColor.opacity(0.85) : Color.gray.opacity(0.15))
                .foregroundStyle(message.isUser ? .white : .primary)
                .cornerRadius(12)
            if !message.isUser { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack {
            TextField("Ask about this location...", text: $draftText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.gray.opacity(0.1))
                .cornerRadius(20)
                .onSubmit { send() }
                .disabled(!ai.isAvailable)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
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
