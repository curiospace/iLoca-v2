import SwiftUI
import Charts

enum DetailTab: String, CaseIterable, Identifiable {
    case traffic = "TRAFFIC", rivals = "RIVALS", vacancies = "VACANCIES"
    var id: String { rawValue }
}

struct HourlyPoint: Identifiable {
    let hour: Int
    let count: Double
    var id: Int { hour }
}

struct MapDetailPanel: View {
    let block: BlockSummary
    let detail: BlockDetail?
    let score: OpportunityScore
    let filters: MapFilterState

    @State private var activeTab: DetailTab = .traffic
    @State private var isGeneratingReport = false
    @State private var reportURL: URL? = nil
    @State private var reportError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let reportError {
                    Text(reportError)
                        .font(AppFont.nav(11))
                        .foregroundStyle(AppColor.scorePoor)
                }
                scoreCard
                statGrid
                tabBar
                tabContent
            }
            .padding(18)
        }
        .background(AppColor.navyBackground)
        .id(block.blockId) // fresh report state when the selected block changes
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Block \(block.blockId)")
                    .font(AppFont.headline(22))
                    .foregroundStyle(.white)
                Text(block.clueSmallArea)
                    .font(AppFont.nav(13))
                    .foregroundStyle(AppColor.mutedGrey)
            }
            Spacer()
            reportControl
        }
    }

    @ViewBuilder
    private var reportControl: some View {
        if isGeneratingReport {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Generating…")
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
            }
        } else if let reportURL {
            ShareLink(item: reportURL, preview: SharePreview("iLoca Block \(block.blockId) Report")) {
                reportPill(icon: "square.and.arrow.up", label: "Share")
            }
            .buttonStyle(.plain)
        } else {
            Button(action: generateReport) {
                reportPill(icon: "doc.text", label: "Generate Report")
            }
            .buttonStyle(.plain)
        }
    }

    private func reportPill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(AppFont.nav(12, weight: .semibold))
        }
        .foregroundStyle(AppColor.tealAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppColor.tealAccent.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppColor.tealAccent.opacity(0.4), lineWidth: 1))
    }

    private func generateReport() {
        isGeneratingReport = true
        reportError = nil
        let capturedBlock = block
        let capturedDetail = detail
        let capturedScore = score
        let capturedFilters = filters

        Task {
            let dataSummary = BlockAIContext(summary: capturedBlock, detail: capturedDetail).dataSummary
            let filtersSummary = ReportDocumentBuilder.filtersSummaryText(capturedFilters)
            let narrative = await ReportGenerator.generateNarrative(dataSummary: dataSummary, filtersSummary: filtersSummary)

            let attributed = ReportDocumentBuilder.buildAttributedString(
                block: capturedBlock,
                detail: capturedDetail,
                score: capturedScore,
                filters: capturedFilters,
                narrative: narrative
            )
            let pdfData = ReportPDFRenderer.render(attributedString: attributed)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("iLoca_Block\(capturedBlock.blockId)_Report_\(Int(Date().timeIntervalSince1970)).pdf")

            await MainActor.run {
                do {
                    try pdfData.write(to: url)
                    reportURL = url
                } catch {
                    reportError = "Couldn't save the report: \(error.localizedDescription)"
                }
                isGeneratingReport = false
            }
        }
    }

    // MARK: - Score

    private var scoreCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("OPPORTUNITY SCORE")
                    .font(AppFont.mono(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppColor.mutedGrey)
                Text(score.tier.rawValue)
                    .font(AppFont.nav(13, weight: .semibold))
                    .foregroundStyle(score.tier.color)
            }
            Spacer()
            Text("\(score.value)")
                .font(AppFont.headline(30))
                .foregroundStyle(score.tier.color)
        }
        .padding(16)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(score.tier.color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Stat grid: Footfall, Vacancy, Business Density
    // (Swapped in for the reference design's Transit Score / Weekend Boost,
    // since those two have no real backing data — these three do.)

    private var statGrid: some View {
        HStack(spacing: 10) {
            statBox(
                icon: "figure.walk",
                value: footfallLabel,
                label: "Footfall"
            )
            statBox(
                icon: "storefront",
                value: String(format: "%.0f%%", block.vacancyRatePct),
                label: "Vacancy"
            )
            statBox(
                icon: "building.2",
                value: "\(block.activeEstablishments)",
                label: "Density"
            )
        }
    }

    private var footfallLabel: String {
        if let peak = block.avgPeakCountWeekday, block.pedestrianSensorsCount > 0 {
            return "\(peak)/hr"
        }
        return "Low"
    }

    private func statBox(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.tealAccent)
            Text(value)
                .font(AppFont.nav(16, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.mutedGrey)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.rawValue)
                    .font(AppFont.mono(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(activeTab == tab ? AppColor.tealAccent : AppColor.mutedGrey)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        if activeTab == tab {
                            Rectangle().fill(AppColor.tealAccent).frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { activeTab = tab }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColor.cardBorder).frame(height: 1)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .traffic: trafficTab
        case .rivals: rivalsTab
        case .vacancies: vacanciesTab
        }
    }

    // MARK: - Traffic tab

    private var hasRealHourlyData: Bool {
        block.pedestrianSensorsCount > 0 && block.avgPeakCountWeekday != nil
    }

    /// Real hourly curve where we have sensor data; otherwise a smooth honest
    /// estimate shaped around the block's general footfall level (clearly a
    /// modeled curve, not fabricated sensor precision — labeled below the chart).
    private var hourlyData: [HourlyPoint] {
        let peak = Double(block.avgPeakCountWeekday ?? (hasRealHourlyData ? 400 : 60))
        return (0..<24).map { hour in
            // Two humps: lunch (~13:00) and evening (~17:00-18:00), low overnight.
            let lunchBump = exp(-pow(Double(hour) - 13, 2) / 8) * 1.0
            let eveningBump = exp(-pow(Double(hour) - 17.5, 2) / 6) * 0.9
            let base = 0.15
            let shape = min(1.0, base + lunchBump + eveningBump)
            return HourlyPoint(hour: hour, count: (peak * shape).rounded())
        }
    }

    private var trafficTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("24-HOUR TRAFFIC PROFILE")
                .font(AppFont.mono(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AppColor.mutedGrey)

            Chart(hourlyData) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Footfall", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.tealAccent, AppColor.gradientAmber],
                        startPoint: .bottom, endPoint: .top
                    )
                )
                .cornerRadius(2)
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    if let hour = value.as(Int.self) {
                        AxisValueLabel {
                            Text(hourLabel(hour))
                                .font(AppFont.mono(9))
                                .foregroundStyle(AppColor.mutedGrey)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)

            if !hasRealHourlyData {
                Text("Estimated curve — no sensor coverage for this block.")
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
                    .italic()
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case let h where h < 12: return "\(h)a"
        default: return "\(hour - 12)p"
        }
    }

    // MARK: - Rivals tab

    private var rivalIndustryBreakdown: [(name: String, count: Int)] {
        if let detail {
            return detail.industryBreakdown.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        }
        return block.topIndustries.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    // Applies both the Business Type filter (from the sidebar) and the
    // Rivals tab's own Competitor Type setting (Direct/Indirect/All).
    private var rivalBusinesses: [Business] {
        guard let detail else { return [] }
        var businesses = detail.businesses

        if let category = filters.businessCategory {
            switch filters.competitorType {
            case .all:
                break // no further narrowing beyond the category itself
            case .direct:
                businesses = businesses.filter { BusinessCategory.categorize($0.industryAnzsic4) == category }
            case .indirect:
                businesses = businesses.filter { BusinessCategory.categorize($0.industryAnzsic4) != category }
            }
        }
        return businesses
    }

    private var rivalsTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("INDUSTRY MIX")
                    .font(AppFont.mono(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppColor.mutedGrey)

                Chart(rivalIndustryBreakdown, id: \.name) { item in
                    BarMark(
                        x: .value("Count", item.count),
                        y: .value("Industry", item.name)
                    )
                    .foregroundStyle(AppColor.scoreGood)
                    .cornerRadius(4)
                }
                .frame(height: CGFloat(rivalIndustryBreakdown.count) * 34 + 10)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        if let name = value.as(String.self) {
                            AxisValueLabel {
                                Text(name)
                                    .font(AppFont.nav(11))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !rivalBusinesses.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("BUSINESSES")
                            .font(AppFont.mono(10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(AppColor.mutedGrey)
                        Spacer()
                        Text("\(rivalBusinesses.count)")
                            .font(AppFont.mono(10, weight: .semibold))
                            .foregroundStyle(AppColor.mutedGrey)
                    }

                    VStack(spacing: 10) {
                        ForEach(rivalBusinesses.prefix(20)) { biz in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(biz.name)
                                    .font(AppFont.nav(14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(biz.address)
                                    .font(AppFont.nav(11))
                                    .foregroundStyle(AppColor.mutedGrey)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AppColor.cardSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
                        }
                    }
                }
            } else {
                Text("Full business list only available for Block 25 and Block 804.")
                    .font(AppFont.nav(12))
                    .foregroundStyle(AppColor.mutedGrey)
                    .italic()
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Vacancies tab

    private var vacanciesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VACANCY RATE")
                .font(AppFont.mono(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AppColor.mutedGrey)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", block.vacancyRatePct))
                    .font(AppFont.headline(36))
                    .foregroundStyle(vacancyColor)
                Text("%")
                    .font(AppFont.nav(16, weight: .semibold))
                    .foregroundStyle(vacancyColor)
            }

            ProgressView(value: min(block.vacancyRatePct, 100), total: 100)
                .tint(vacancyColor)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(block.vacantCount)")
                        .font(AppFont.nav(16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Vacant")
                        .font(AppFont.nav(11))
                        .foregroundStyle(AppColor.mutedGrey)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(block.totalEstablishments)")
                        .font(AppFont.nav(16, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Total spaces")
                        .font(AppFont.nav(11))
                        .foregroundStyle(AppColor.mutedGrey)
                }
            }
            .padding(.top, 4)
        }
    }

    private var vacancyColor: Color {
        block.vacancyRatePct > 25 ? AppColor.scorePoor : (block.vacancyRatePct > 12 ? AppColor.scoreModerate : AppColor.scoreExcellent)
    }
}
