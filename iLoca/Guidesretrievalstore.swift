//
//  GuideChunk.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import Foundation
import PDFKit
import NaturalLanguage

// MARK: - A single indexed piece of a guide, small enough to hand to the model
// as grounding context, with its precomputed sentence-embedding vector.

struct GuideChunk: Identifiable {
    let id = UUID()
    let bucket: GuideBucket
    let text: String
    var embedding: [Double]?
}

/// Loads all four bundled guide PDFs, splits them into paragraph-sized chunks,
/// and embeds each chunk on-device with NaturalLanguage's sentence embedding.
/// This is what lets the AI panel answer questions that span more than one
/// guide — retrieval runs across every bucket, not just the one currently open.
@Observable
class GuidesRetrievalStore {
    private(set) var chunks: [GuideChunk] = []
    /// Full extracted text of each guide (they're short: ~4k tokens in total).
    private(set) var fullText: [GuideBucket: String] = [:]
    private(set) var isReady = false
    private(set) var loadError: String?

    private let embedder = NLEmbedding.sentenceEmbedding(for: .english)

    /// Call once (e.g. from GuidesView's .task) — safe to call again, it's a no-op
    /// once already indexed.
    func loadAndIndex() async {
        guard !isReady else { return }

        var built: [GuideChunk] = []
        var texts: [GuideBucket: String] = [:]
        var missing: [String] = []

        for bucket in GuideBucket.allCases {
            guard let url = Bundle.main.url(forResource: bucket.pdfResourceName, withExtension: "pdf"),
                  let doc = PDFDocument(url: url) else {
                missing.append(bucket.pdfResourceName)
                continue
            }
            let fullText = extractText(from: doc)
            texts[bucket] = fullText
            for piece in chunk(text: fullText) {
                built.append(GuideChunk(bucket: bucket, text: piece))
            }
        }

        for i in built.indices {
            built[i].embedding = embedder?.vector(for: built[i].text)
        }

        await MainActor.run {
            self.chunks = built
            self.fullText = texts
            self.isReady = true
            if !missing.isEmpty {
                self.loadError = "Missing from app bundle: \(missing.joined(separator: ", ")).pdf"
            }
        }
    }

    private func extractText(from doc: PDFDocument) -> String {
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        return text
    }

    /// Groups lines into ~500-character chunks so retrieval can pick out the
    /// relevant passage rather than a whole page. (These PDFs have no blank lines
    /// between paragraphs, so splitting on "\n\n" would give one chunk per page.)
    private func chunk(text: String) -> [String] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let target = 500
        var result: [String] = []
        var buffer = ""
        for line in lines {
            if !buffer.isEmpty && buffer.count + line.count > target {
                result.append(buffer)
                buffer = ""
            }
            buffer += (buffer.isEmpty ? "" : "\n") + line
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result.filter { $0.count > 40 }
    }

    /// Returns the top-K most relevant chunks across ALL four guides for a query.
    func topMatches(for query: String, k: Int = 6) -> [GuideChunk] {
        guard let embedder, let queryVector = embedder.vector(for: query) else {
            return Array(chunks.prefix(k))
        }
        let scored: [(GuideChunk, Double)] = chunks.compactMap { chunk in
            guard let v = chunk.embedding else { return nil }
            return (chunk, cosineDistance(queryVector, v))
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(k).map { $0.0 }
    }

    private func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }
        var dot = 0.0, magA = 0.0, magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        guard magA > 0, magB > 0 else { return .greatestFiniteMagnitude }
        return 1 - (dot / (sqrt(magA) * sqrt(magB)))
    }
}