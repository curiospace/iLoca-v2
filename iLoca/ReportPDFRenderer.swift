//
//  ReportPDFRenderer.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import AppKit
import CoreText

/// Renders an NSAttributedString into a paginated PDF, standard CoreText
/// pagination pattern. Not tied to any specific report content — reusable
/// for any future PDF export.
enum ReportPDFRenderer {
    static func render(
        attributedString: NSAttributedString,
        pageSize: CGSize = CGSize(width: 612, height: 792), // US Letter, points
        margin: CGFloat = 54
    ) -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return Data() }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textRect = CGRect(
            x: margin, y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )
        let path = CGPath(rect: textRect, transform: nil)

        var currentRange = CFRange(location: 0, length: 0)

        repeat {
            context.beginPDFPage(nil)

            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)

            context.endPDFPage()

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange = CFRange(
                location: currentRange.location + visibleRange.length,
                length: 0
            )
        } while currentRange.location < attributedString.length

        context.closePDF()
        return pdfData as Data
    }
}