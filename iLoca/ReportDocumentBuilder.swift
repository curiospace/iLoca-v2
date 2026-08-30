//
//  ReportDocumentBuilder.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import AppKit

/// Composes the report's content as an NSAttributedString (fed to
/// ReportPDFRenderer) and, separately, a plain-text filters summary shared by
/// both the PDF's "Search Criteria" section and the AI narrative prompt so
/// they never drift out of sync with each other.
enum ReportDocumentBuilder {

    // MARK: - Filters summary (shared between PDF and AI prompt)

    static func filtersSummaryText(_ filters: MapFilterState) -> String {
        var lines: [String] = []
        lines.append("Business Type: \(filters.businessCategory?.rawValue ?? "Any")")
        lines.append("Footfall Level: \(filters.footfallLevel.rawValue)")
        lines.append("Time of Day: \(filters.timesOfDay.isEmpty ? "Any" : filters.timesOfDay.map(\.rawValue).joined(separator: ", "))")
        lines.append("Day Type: \(filters.dayTypes.isEmpty ? "Any" : filters.dayTypes.map(\.rawValue).joined(separator: ", "))")
        lines.append("Competitor Type: \(filters.competitorType.rawValue)")
        lines.append("Search Radius: \(filters.searchRadius.label)")
        lines.append("Competition Preference: \(filters.competitionPreference.rawValue)")
        lines.append("Map Overlays Active: \(overlaysSummary(filters))")
        return lines.joined(separator: "\n")
    }

    private static func overlaysSummary(_ filters: MapFilterState) -> String {
        var active: [String] = []
        if filters.showCompetitorMarkers { active.append("Competitor Markers") }
        if filters.showFootfallZones { active.append("Footfall Zones") }
        if filters.showVacancyZones { active.append("Vacancy") }
        if filters.showDevelopmentSites { active.append("Development Sites (demo, no live data)") }
        if filters.showTransitStops { active.append("Transit Stops (demo, no live data)") }
        return active.isEmpty ? "None" : active.joined(separator: ", ")
    }

    // MARK: - Full report content

    static func buildAttributedString(
        block: BlockSummary,
        detail: BlockDetail?,
        score: OpportunityScore,
        filters: MapFilterState,
        narrative: String
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        func addTitle(_ text: String) {
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 22),
                .foregroundColor: NSColor.black
            ]))
        }
        func addHeading(_ text: String) {
            let spacer = NSMutableParagraphStyle()
            spacer.paragraphSpacingBefore = 14
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.black,
                .paragraphStyle: spacer
            ]))
        }
        func addBody(_ text: String) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 4
            paragraph.lineSpacing = 2
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]))
        }
        func addRow(_ label: String, _ value: String) {
            let bold = NSMutableAttributedString(string: "\(label): ", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.black
            ])
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 3
            bold.append(NSAttributedString(string: value + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]))
            result.append(bold)
        }

        addTitle("iLoca Location Report")
        addBody("Block \(block.blockId) · \(block.clueSmallArea)")
        addBody("Generated \(dateString())")

        addHeading("AI Analysis")
        addBody(narrative)

        addHeading("Opportunity Score")
        addRow("Score", "\(score.value) / 100 — \(score.tier.rawValue)")

        addHeading("Key Stats")
        addRow("Footfall", footfallLabel(block))
        addRow("Vacancy Rate", String(format: "%.1f%%", block.vacancyRatePct))
        addRow("Active Businesses (Density)", "\(block.activeEstablishments)")
        addRow("Vacant Spaces", "\(block.vacantCount) of \(block.totalEstablishments) total")

        addHeading("Search Criteria Applied")
        for line in filtersSummaryText(filters).split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                addRow(String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
            } else {
                addBody(String(line))
            }
        }

        addHeading("Industry Mix")
        let industries = detail?.industryBreakdown ?? block.topIndustries
        if industries.isEmpty {
            addBody("No industry breakdown available for this block.")
        } else {
            for (name, count) in industries.sorted(by: { $0.value > $1.value }).prefix(15) {
                addBody("• \(name): \(count)")
            }
        }

        if let detail {
            addHeading("Businesses (\(detail.businesses.count) total\(detail.businesses.count > 40 ? ", showing first 40" : ""))")
            for biz in detail.businesses.prefix(40) {
                addBody("• \(biz.name) — \(biz.industryAnzsic4) — \(biz.address)")
            }
        } else {
            addHeading("Businesses")
            addBody("Named business data is only available for Block 25 and Block 804. This block has category-level data only, shown above under Industry Mix.")
        }

        addHeading("Data Notes")
        addBody("Business and vacancy figures are sourced from City of Melbourne CLUE open data. Foot traffic is drawn from real pedestrian sensor data where available; blocks without sensor coverage are honestly shown as Low rather than estimated. Competitor radius search is approximated using block centroids, not exact per-business coordinates. This report's AI analysis was generated entirely on-device using Apple Intelligence — nothing left this Mac.")

        return result
    }

    private static func footfallLabel(_ block: BlockSummary) -> String {
        if let peak = block.avgPeakCountWeekday, block.pedestrianSensorsCount > 0 {
            return "\(peak)/hr (real sensor data)"
        }
        return "Low (no sensor coverage for this block)"
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}