//
//  PDFKitView.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI
import PDFKit

/// Thin NSViewRepresentable wrapper so SwiftUI can host AppKit's PDFView.
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct GuidePDFViewerSheet: View {
    let bucket: GuideBucket
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(bucket.documentTitle)
                    .font(AppFont.nav(14, weight: .semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if let url = Bundle.main.url(forResource: bucket.pdfResourceName, withExtension: "pdf") {
                PDFKitView(url: url)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("\(bucket.pdfResourceName).pdf wasn't found in the app bundle.")
                        .foregroundStyle(.secondary)
                    Text("Add it to the Xcode project with target membership checked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 720)
    }
}