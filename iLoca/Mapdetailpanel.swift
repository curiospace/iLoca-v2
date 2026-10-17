import SwiftUI
import Charts

enum DetailTab: String, CaseIterable, Identifiable {
    case traffic = "TRAFFIC", rivals = "RIVALS", vacancies = "VACANT", parking = "PARKING"
    var id: String { rawValue }
}

struct MapDetailPanel: View {
    let block: CityBlock
    let store: CityDataStore

    @State private var activeTab: DetailTab = .traffic
    @State private var isGeneratingReport = false
    @State private var reportURL: URL? = nil
    @State private var reportError: String? = nil
    @Environment(\.reportIssue) private var reportIssue

    private var filters: MapFilterState { store.filters }
    private var metrics: BlockMetrics? { store.metrics(for: block) }
    private var premises: [BusinessRecord]? { store.premisesByBlock[block.blockId] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                FreshnessLine(store: store)
                if let reportError {
                    Text(reportError)
                        .font(AppFont.nav(11))
                        .foregroundStyle(AppColor.scorePoor)
                }
                if let metrics {
                    ScoreCard(score: metrics.score)
                }
                ConfidenceCard(confidence: store.confidence(for: block))
                statGrid
                tabBar
                tabContent
                reportIssueLink
            }
            .padding(18)
            .padding(.bottom, 110) // clear of the floating Loca button
        }
        .background(AppColor.navyBackground)
        .id(block.blockId) // fresh report state when the selected block changes
        .task(id: block.blockId) {
            async let premises: Void = store.loadPremises(for: block.blockId)
            async let parking: Void = store.refreshOnStreetIfStale()
            _ = await (premises, parking)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Block \(block.blockId)")
                    .font(AppFont.headline(22))
                    .foregroundStyle(AppColor.textPrimary)
                Text(block.area)
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
        guard let metrics else { return }
        isGeneratingReport = true
        reportError = nil
        let block = self.block
        let confidence = store.confidence(for: block)
        let filtersSummary = Grounding.filtersSummary(filters)

        Task {
            await store.loadPremises(for: block.blockId)
            let narrative = await ReportGenerator.generateNarrative(
                blockContext: Grounding.blockContext(store, block: block),
                compactContext: Grounding.blockContext(store, block: block, compact: true),
                filtersSummary: filtersSummary)
            let attributed = ReportDocumentBuilder.buildAttributedString(.init(
                block: block,
                metrics: metrics,
                confidence: confidence,
                filtersSummary: filtersSummary,
                premises: store.premisesByBlock[block.blockId],
                narrative: narrative.text,
                aiProvider: narrative.provider,
                censusYear: store.censusYear,
                freshness: store.freshnessLine,
                datasets: store.snapshot?.datasets ?? [],
                parking: store.parking(for: block),
                parkingNote: store.onStreet?.latestReport.map { "(live, \(MelbourneTime.dayTime($0)))" } ?? ""
            ))
            let pdfData = ReportPDFRenderer.render(attributedString: attributed)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("iLoca_Block\(block.blockId)_Report_\(Int(Date().timeIntervalSince1970)).pdf")
            do {
                try pdfData.write(to: url)
                reportURL = url
            } catch {
                reportError = "Couldn't save the report: \(error.localizedDescription)"
            }
            isGeneratingReport = false
        }
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            statBox(icon: "figure.walk",
                    value: metrics?.footfall.map { "\(Int($0.rounded()))/hr" } ?? "No sensor",
                    label: "Foot traffic · \(filters.timeWindowLabel)")
            statBox(icon: "storefront",
                    value: String(format: "%.0f%%", block.vacancyRatePct),
                    label: "Vacancy (\(block.vacantPremises) of \(block.totalPremises))")
            statBox(icon: "building.2", value: "\(block.activeEstablishments)", label: "Active businesses")
            statBox(icon: "person.2.wave.2",
                    value: "\(metrics?.competitorsInRadius ?? 0)",
                    label: "\(competitorNoun) within \(filters.searchRadius.label)")
        }
    }

    private var competitorNoun: String {
        switch filters.competitorType {
        case .direct: return filters.businessCategory.map { "\($0.rawValue) rivals" } ?? "Businesses"
        case .indirect: return filters.businessCategory == nil ? "Businesses" : "Indirect rivals"
        case .all: return "Businesses"
        }
    }

    private func statBox(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.tealAccent)
            Text(value)
                .font(AppFont.nav(16, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.nav(10))
                .foregroundStyle(AppColor.mutedGrey)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
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
        case .parking: parkingTab
        }
    }

    // MARK: - Traffic tab (real Pedestrian Counting System averages)

    private struct HourPoint: Identifiable {
        let hour: Int
        let count: Double
        let day: DayType
        var id: String { "\(day.rawValue)-\(hour)" }
    }

    private var hourlyPoints: [HourPoint] {
        DayType.allCases.flatMap { day -> [HourPoint] in
            guard let profile = store.hourlyProfile(for: block, dayType: day) else { return [] }
            return profile.enumerated().compactMap { hour, value in
                value.map { HourPoint(hour: hour, count: $0, day: day) }
            }
        }
    }

    @ViewBuilder
    private var trafficTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AVERAGE PEOPLE PER HOUR")
                .font(AppFont.mono(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AppColor.mutedGrey)

            if let sensor = store.sensor(for: block), !hourlyPoints.isEmpty {
                let selected = Set(filters.selectedHours)
                Chart {
                    ForEach(Array(selected), id: \.self) { hour in
                        RectangleMark(xStart: .value("Start", Double(hour) - 0.5), xEnd: .value("End", Double(hour) + 0.5))
                            .foregroundStyle(AppColor.tealAccent.opacity(0.08))
                    }
                    ForEach(hourlyPoints) { point in
                        LineMark(x: .value("Hour", Double(point.hour)), y: .value("People/hr", point.count))
                            .foregroundStyle(by: .value("Day", point.day.rawValue))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartForegroundStyleScale([DayType.weekday.rawValue: AppColor.tealAccent,
                                            DayType.weekend.rawValue: AppColor.gradientAmber])
                .chartLegend(position: .top, alignment: .leading)
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisValueLabel {
                            if let hour = value.as(Double.self) {
                                Text(hourLabel(Int(hour)))
                                    .font(AppFont.mono(9))
                                    .foregroundStyle(AppColor.mutedGrey)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(AppColor.textPrimary.opacity(0.05))
                        AxisValueLabel().font(AppFont.mono(9)).foregroundStyle(AppColor.mutedGrey)
                    }
                }
                .frame(height: 160)

                Text("Sensor: \(sensor.description), \(Int(block.sensorDistanceMetres ?? 0)) m from the block centre. Shaded hours = your Time of Day filter.")
                    .font(AppFont.nav(10))
                    .foregroundStyle(AppColor.mutedGrey)
                if let start = store.snapshot?.footfallWindowStart, let end = store.snapshot?.footfallWindowEnd {
                    Text("Averaged over \(MelbourneTime.day(start)) – \(MelbourneTime.day(end)).")
                        .font(AppFont.nav(10))
                        .foregroundStyle(AppColor.mutedGrey)
                }
            } else {
                emptyNote("No pedestrian sensor within \(Int(OpenDataClient.sensorMatchRadius)) m of this block, so foot traffic is unknown here. It isn't assumed low. The Opportunity Score uses vacancy and business activity instead, and confidence is reduced.")
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

    private var industryMix: [(name: String, count: Int)] {
        block.industryMix.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }
    }

    /// Named businesses filtered by the Business Type + Competitor Type filters.
    private var rivalBusinesses: [BusinessRecord] {
        let businesses = (premises ?? []).filter { !$0.isVacant }
        guard let category = filters.businessCategory else { return businesses }
        switch filters.competitorType {
        case .all: return businesses
        case .direct: return businesses.filter { $0.category == category }
        case .indirect: return businesses.filter { $0.category != category }
        }
    }

    private var rivalsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("INDUSTRY MIX")
                    .font(AppFont.mono(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppColor.mutedGrey)

                if industryMix.isEmpty {
                    emptyNote("No active businesses recorded in this block.")
                } else {
                    Chart(industryMix, id: \.name) { item in
                        BarMark(x: .value("Count", item.count), y: .value("Industry", item.name))
                            .foregroundStyle(AppColor.scoreGood)
                            .cornerRadius(4)
                            .annotation(position: .trailing) {
                                Text("\(item.count)").font(AppFont.mono(9)).foregroundStyle(AppColor.mutedGrey)
                            }
                    }
                    .frame(height: CGFloat(industryMix.count) * 30 + 10)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { value in
                            if let name = value.as(String.self) {
                                AxisValueLabel {
                                    Text(name).font(AppFont.nav(10)).foregroundStyle(AppColor.textPrimary.opacity(0.85))
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if filters.businessCategory == nil {
                emptyNote("Pick a Business Type in the sidebar to see direct and indirect competitors.")
            } else {
                Text(filters.competitorType.explanation)
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
            }

            premisesList(
                title: filters.businessCategory == nil ? "BUSINESSES" : filters.competitorType.rawValue.uppercased(),
                items: rivalBusinesses,
                subtitle: { "\($0.industry) · \($0.address)" }
            )
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
                stat("\(block.vacantPremises)", "Vacant")
                stat("\(block.totalPremises)", "Total premises")
            }

            premisesList(title: "VACANT PREMISES", items: (premises ?? []).filter(\.isVacant), subtitle: { _ in nil },
                         titleFor: { $0.address })
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(AppFont.nav(16, weight: .bold)).foregroundStyle(AppColor.textPrimary)
            Text(label).font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
        }
    }

    private var vacancyColor: Color {
        block.vacancyRatePct > 25 ? AppColor.scorePoor : (block.vacancyRatePct > 12 ? AppColor.scoreModerate : AppColor.scoreExcellent)
    }

    // MARK: - Parking tab (off-street census + live on-street sensors)

    private var parkingTab: some View {
        let parking = store.parking(for: block)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ON-STREET, LIVE")
                        .font(AppFont.mono(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(AppColor.mutedGrey)
                    Spacer()
                    if store.onStreetLoading { ProgressView().controlSize(.mini) }
                }
                if let share = parking.freeShare {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(parking.freeBays)")
                            .font(AppFont.headline(32))
                            .foregroundStyle(Self.freeColor(share))
                        Text("of \(parking.bayCount) sensor bays free within \(filters.searchRadius.label)")
                            .font(AppFont.nav(12))
                            .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                    }
                    ProgressView(value: share).tint(Self.freeColor(share))
                    if let report = store.onStreet?.latestReport {
                        Text("Sensors last reported \(MelbourneTime.dayTime(report)). Refreshes every 5 minutes. Only bays fitted with sensors are counted.")
                            .font(AppFont.nav(10))
                            .foregroundStyle(AppColor.mutedGrey)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let error = store.onStreetError {
                    Text(error).font(AppFont.nav(11)).foregroundStyle(AppColor.scorePoor)
                } else if store.onStreet != nil {
                    emptyNote("No sensor-fitted on-street bays within \(filters.searchRadius.label).")
                }
            }
            .padding(14)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text("OFF-STREET\(store.snapshot?.offStreet.map { " · \($0.censusYear) CENSUS" } ?? "")")
                    .font(AppFont.mono(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppColor.mutedGrey)
                HStack(spacing: 20) {
                    stat("\(parking.carParks.count)", "Public car parks within \(filters.searchRadius.label)")
                    stat("\(parking.publicSpaces.formatted())", "Public spaces")
                }
                stat("\(parking.privateSpacesInBlock.formatted())", "Private spaces in this block (tenants/staff)")

                if store.snapshot?.offStreet == nil {
                    emptyNote("Off-street parking data didn't load. Try refreshing on the Info tab.")
                }
                ForEach(parking.carParks.prefix(8), id: \.carPark.id) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("P")
                            .font(AppFont.nav(11, weight: .bold))
                            .foregroundStyle(AppColor.textPrimary)
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5).fill(AppColor.gradientRoyalBlue))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.carPark.address)
                                .font(AppFont.nav(12, weight: .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(2)
                            Text("\(item.carPark.spaces.formatted()) spaces · \(Int(item.distance.rounded())) m away")
                                .font(AppFont.nav(10))
                                .foregroundStyle(AppColor.mutedGrey)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(AppColor.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            emptyNote("Parking is shown for context. It isn't part of the Opportunity Score.")
        }
    }

    static func freeColor(_ share: Double) -> Color {
        share >= 0.5 ? AppColor.scoreExcellent : share >= 0.2 ? AppColor.scoreModerate : AppColor.scorePoor
    }

    // MARK: - Shared list

    @ViewBuilder
    private func premisesList(
        title: String,
        items: [BusinessRecord],
        subtitle: @escaping (BusinessRecord) -> String?,
        titleFor: @escaping (BusinessRecord) -> String = { $0.name }
    ) -> some View {
        if store.premisesLoading.contains(block.blockId) && premises == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading premises from City of Melbourne…").font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
            }
        } else if let error = store.premisesErrors[block.blockId], premises == nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(error).font(AppFont.nav(11)).foregroundStyle(AppColor.scorePoor)
                Button("Retry") { Task { await store.loadPremises(for: block.blockId) } }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.tealAccent)
            }
        } else if premises != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(AppFont.mono(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(AppColor.mutedGrey)
                    Spacer()
                    Text("\(items.count)")
                        .font(AppFont.mono(10, weight: .semibold))
                        .foregroundStyle(AppColor.mutedGrey)
                }
                if items.isEmpty {
                    emptyNote("None recorded in the \(store.censusYear) census.")
                }
                LazyVStack(spacing: 8) {
                    ForEach(items.prefix(60)) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(item.category?.color ?? AppColor.mutedGrey)
                                .frame(width: 7, height: 7)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(titleFor(item))
                                    .font(AppFont.nav(13, weight: .semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                if let sub = subtitle(item) {
                                    Text(sub)
                                        .font(AppFont.nav(10))
                                        .foregroundStyle(AppColor.mutedGrey)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppColor.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                if items.count > 60 {
                    Text("+ \(items.count - 60) more").font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
                }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(AppFont.nav(12))
            .foregroundStyle(AppColor.mutedGrey)
            .italic()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var reportIssueLink: some View {
        Button {
            reportIssue(IssueContext(
                blockId: block.blockId,
                blockArea: block.area,
                score: metrics?.score.value,
                confidence: store.confidence(for: block).level.rawValue,
                dataFreshness: store.freshnessLine
            ))
        } label: {
            Label("Something look wrong? Report an issue", systemImage: "flag")
                .font(AppFont.nav(11, weight: .semibold))
                .foregroundStyle(AppColor.mutedGrey)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}
