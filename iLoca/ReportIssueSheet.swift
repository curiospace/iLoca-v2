import SwiftUI

/// "Report an issue" form, opened from the Info tab's corner button or the flag
/// under any AI answer.
struct ReportIssueSheet: View {
    let context: IssueContext
    @Environment(\.dismiss) private var dismiss

    @State private var kind: IssueKind
    @State private var details = ""
    @State private var includeContext = true
    @State private var savedURL: URL?
    @State private var error: String?
    @State private var copied = false

    init(context: IssueContext) {
        self.context = context
        _kind = State(initialValue: context.flaggedAnswer != nil ? .unexpectedAI : .incorrectData)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flag.fill").foregroundStyle(AppColor.scorePoor)
                Text("Report an issue")
                    .font(AppFont.headline(20))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(AppColor.mutedGrey)
                }
                .buttonStyle(.plain)
            }

            if let savedURL {
                savedState(savedURL)
            } else {
                form
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(AppColor.navyBackground)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Help us improve iLoca. Flag incorrect data, a misleading recommendation or unexpected AI behaviour.")
                .font(AppFont.nav(12))
                .foregroundStyle(AppColor.mutedGrey)

            VStack(alignment: .leading, spacing: 8) {
                label("WHAT KIND OF ISSUE?")
                HStack(spacing: 8) {
                    ForEach(IssueKind.allCases) { k in
                        Button { kind = k } label: {
                            VStack(spacing: 6) {
                                Image(systemName: k.icon).font(.system(size: 15))
                                Text(k.rawValue)
                                    .font(AppFont.nav(11, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(kind == k ? AppColor.tealAccent : AppColor.textPrimary.opacity(0.8))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .padding(6)
                            .background(kind == k ? AppColor.tealAccent.opacity(0.12) : AppColor.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(kind == k ? AppColor.tealAccent : AppColor.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                label("WHAT HAPPENED?")
                TextEditor(text: $details)
                    .font(AppFont.nav(13))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(8)
                    .frame(height: 110)
                    .background(AppColor.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
            }

            if !contextLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $includeContext) {
                        Text("Include this context")
                            .font(AppFont.nav(12, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(AppColor.tealAccent)
                    if includeContext {
                        ForEach(contextLines, id: \.self) { line in
                            Text(line)
                                .font(AppFont.nav(11))
                                .foregroundStyle(AppColor.mutedGrey)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(12)
                .background(AppColor.cardSurface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let error {
                Text(error).font(AppFont.nav(11)).foregroundStyle(AppColor.scorePoor)
            }

            HStack {
                Text("Saved on this Mac. Nothing is sent until you share it.")
                    .font(AppFont.nav(10))
                    .foregroundStyle(AppColor.mutedGrey)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.mutedGrey)
                Button(action: save) {
                    Text("Save report")
                        .font(AppFont.nav(13, weight: .semibold))
                        .foregroundStyle(AppColor.navyBackground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColor.tealAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
    }

    private func savedState(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Report saved. Thank you!", systemImage: "checkmark.circle.fill")
                .font(AppFont.nav(14, weight: .semibold))
                .foregroundStyle(AppColor.tealAccent)
            Text("Send it to the iLoca team by sharing the file (Mail, Messages, AirDrop) or copying its contents.")
                .font(AppFont.nav(12))
                .foregroundStyle(AppColor.mutedGrey)
            Text(url.lastPathComponent)
                .font(AppFont.mono(11))
                .foregroundStyle(AppColor.textPrimary.opacity(0.8))
            HStack(spacing: 10) {
                ShareLink(item: url) { pill("Share…", icon: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                Button {
                    FeedbackService.copyToClipboard(url)
                    copied = true
                } label: { pill(copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.plain)
                Button { FeedbackService.revealInFinder(url) } label: { pill("Show in Finder", icon: "folder") }
                    .buttonStyle(.plain)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.tealAccent)
            }
        }
    }

    private var contextLines: [String] {
        var lines: [String] = []
        if let id = context.blockId { lines.append("Block \(id)\(context.blockArea.map { " · \($0)" } ?? "")") }
        if let score = context.score { lines.append("Opportunity Score \(score)") }
        if let confidence = context.confidence { lines.append("Confidence \(confidence)") }
        if let q = context.flaggedQuestion { lines.append("Question: \(q)") }
        if let a = context.flaggedAnswer { lines.append("Answer: \(a)") }
        if let p = context.provider { lines.append("AI: \(p)") }
        if let f = context.dataFreshness { lines.append("Data: \(f)") }
        return lines
    }

    private func save() {
        do {
            savedURL = try FeedbackService.save(kind: kind, description: details, context: context, includeContext: includeContext)
            error = nil
        } catch {
            self.error = "Couldn't save the report: \(error.localizedDescription)"
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(AppFont.mono(10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(AppColor.mutedGrey)
    }

    private func pill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppFont.nav(12, weight: .semibold))
            .foregroundStyle(AppColor.tealAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColor.tealAccent.opacity(0.12))
            .clipShape(Capsule())
    }
}
