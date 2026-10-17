import Foundation
import AppKit

/// "Report an issue": lets users flag incorrect data, misleading recommendations
/// or unexpected AI behaviour (Accountability). Reports are saved as local JSON
/// files the user can share with the iLoca team by whatever channel they choose.
/// Nothing is uploaded automatically.
enum IssueKind: String, CaseIterable, Identifiable, Codable {
    case incorrectData = "Incorrect data"
    case misleadingRecommendation = "Misleading recommendation"
    case unexpectedAI = "Unexpected AI behaviour"
    case other = "Something else"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .incorrectData: return "tablecells.badge.ellipsis"
        case .misleadingRecommendation: return "arrow.triangle.branch"
        case .unexpectedAI: return "sparkles"
        case .other: return "ellipsis.bubble"
        }
    }
}

/// Context captured with a report, decided by where it was opened from.
struct IssueContext {
    var blockId: Int? = nil
    var blockArea: String? = nil
    var score: Int? = nil
    var confidence: String? = nil
    var flaggedAnswer: String? = nil
    var flaggedQuestion: String? = nil
    var provider: String? = nil
    var dataFreshness: String? = nil
}

struct IssueReport: Codable {
    let id: UUID
    let createdAt: Date
    let kind: IssueKind
    let description: String
    let blockId: Int?
    let blockArea: String?
    let score: Int?
    let confidence: String?
    let flaggedQuestion: String?
    let flaggedAnswer: String?
    let aiProvider: String?
    let dataFreshness: String?
    let appVersion: String
}

enum FeedbackService {
    static var reportsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("iLoca/Issue Reports", isDirectory: true)
    }

    static func save(kind: IssueKind, description: String, context: IssueContext, includeContext: Bool) throws -> URL {
        let report = IssueReport(
            id: UUID(),
            createdAt: Date(),
            kind: kind,
            description: description,
            blockId: includeContext ? context.blockId : nil,
            blockArea: includeContext ? context.blockArea : nil,
            score: includeContext ? context.score : nil,
            confidence: includeContext ? context.confidence : nil,
            flaggedQuestion: includeContext ? context.flaggedQuestion : nil,
            flaggedAnswer: includeContext ? context.flaggedAnswer : nil,
            aiProvider: includeContext ? context.provider : nil,
            dataFreshness: includeContext ? context.dataFreshness : nil,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: report.createdAt).replacingOccurrences(of: ":", with: "-")
        let url = reportsDirectory.appendingPathComponent("iLoca-issue-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func copyToClipboard(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
