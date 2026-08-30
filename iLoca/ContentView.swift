import SwiftUI
import MapKit

struct ContentView: View {
    @Binding var activeTab: String
    var onNavTap: ((String) -> Void)? = nil
    @Binding var currentBlockLabel: String?
    var ai: LocationAdvisorAI

    @State private var blocksSummary: BlocksSummary?
    @State private var selectedBlockId: Int? = nil
    @State private var selectedBlockDetail: BlockDetail? = nil
    @State private var filters = MapFilterState()

    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631),
            distance: 3200,
            heading: 0,
            pitch: 55
        )
    )

    private var allBlocks: [BlockSummary] {
        blocksSummary?.blocks ?? []
    }

    private var selectedBlock: BlockSummary? {
        allBlocks.first { $0.blockId == selectedBlockId }
    }

    private var maxActiveEstablishments: Int {
        allBlocks.map(\.activeEstablishments).max() ?? 1
    }

    // MARK: - Business category filter
    // Applied two ways at once: (1) to our own block pins, using each block's
    // real top-industries breakdown, and (2) to Apple's own base-map business
    // labels via MapKit's built-in points-of-interest filter — those "Sydney
    // Tools" / "Half Acre" style labels are Apple Maps POIs, not our data, so
    // filtering them needs MapKit's own filter, not ours.

    private func blockMatchesCategory(_ block: BlockSummary) -> Bool {
        guard let category = filters.businessCategory else { return true }
        return block.topIndustries.keys.contains { BusinessCategory.categorize($0) == category }
    }

    private var poiFilter: PointOfInterestCategories {
        switch filters.businessCategory {
        case .cafe:
            return .including([.cafe, .restaurant, .bakery, .foodMarket])
        case .retail:
            return .including([.store, .pharmacy])
        case .services:
            return .including([.bank, .hospital, .fitnessCenter, .laundry, .postOffice, .school])
        case nil:
            return .all
        }
    }

    // MARK: - Footfall filter
    // Real hourly data where we have sensor coverage; everywhere else the
    // block is honestly bucketed as "Low" rather than hidden or faked.

    private func footfallTier(for block: BlockSummary) -> FootfallLevel {
        guard block.pedestrianSensorsCount > 0, let peak = block.avgPeakCountWeekday else { return .low }
        switch peak {
        case ..<150: return .low
        case 150..<350: return .medium
        case 350..<600: return .high
        default: return .veryHigh
        }
    }

    private func blockMatchesFootfall(_ block: BlockSummary) -> Bool {
        filters.footfallLevel == .any || footfallTier(for: block) == filters.footfallLevel
    }

    // MARK: - Combined visible set for our own pins

    private var visibleBlocks: [BlockSummary] {
        allBlocks.filter { blockMatchesCategory($0) && blockMatchesFootfall($0) }
    }

    // MARK: - Competitor markers (Competition filter + "Competitor Markers" overlay)
    // Only meaningful once a block is selected: shows other blocks within the
    // chosen search radius whose category mix matches the chosen competitor type.
    // This is a block-centroid approximation (see MapFilterState.haversineMetres) —
    // not pinpoint-accurate at 250m, but consistent and honest at block level.

    private var competitorBlocks: [BlockSummary] {
        guard filters.showCompetitorMarkers, let selected = selectedBlock else { return [] }
        let selectedCoord = coordinateFor(selected)
        return allBlocks.filter { block in
            guard block.blockId != selected.blockId else { return false }
            let distance = haversineMetres(selectedCoord, coordinateFor(block))
            guard distance <= Double(filters.searchRadius.rawValue) else { return false }

            switch filters.competitorType {
            case .all:
                return true
            case .direct:
                guard let category = filters.businessCategory else { return true }
                return blockMatchesCategory(block) && category == filters.businessCategory
            case .indirect:
                guard filters.businessCategory != nil else { return true }
                return !blockMatchesCategory(block)
            }
        }.filter(matchesCompetitionPreference)
    }

    // Buckets blocks into low/balanced/established competition by active
    // business count relative to the busiest block currently loaded.
    private func matchesCompetitionPreference(_ block: BlockSummary) -> Bool {
        guard maxActiveEstablishments > 0 else { return true }
        let ratio = Double(block.activeEstablishments) / Double(maxActiveEstablishments)
        switch filters.competitionPreference {
        case .any: return true
        case .low: return ratio < 0.33
        case .balanced: return ratio >= 0.33 && ratio <= 0.66
        case .established: return ratio > 0.66
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topNav
            Divider().overlay(AppColor.cardBorder)
            HStack(spacing: 0) {
                MapSidebar(allBlocks: allBlocks, selectedBlockId: $selectedBlockId, filters: filters)
                    .frame(width: 300)

                Divider().overlay(AppColor.cardBorder)

                mapArea
                    .frame(maxWidth: .infinity)

                if let block = selectedBlock {
                    Divider().overlay(AppColor.cardBorder)
                    MapDetailPanel(
                        block: block,
                        detail: selectedBlockDetail,
                        score: OpportunityScore.compute(for: block, maxActiveEstablishments: maxActiveEstablishments),
                        filters: filters
                    )
                    .frame(width: 340)
                }
            }
        }
        .background(AppColor.navyBackground)
        .onAppear {
            blocksSummary = DataLoader.loadAllBlocksSummary()
            ai.startGeneralSession(overview: cityWideOverview)
        }
        .onChange(of: selectedBlockId) { _, newValue in
            loadDetailIfAvailable(for: newValue)
            flyToSelectedBlock()
            currentBlockLabel = selectedBlock.map { "Block \($0.blockId) · \($0.clueSmallArea)" }

            if let block = selectedBlock {
                ai.startNewSession(for: BlockAIContext(summary: block, detail: selectedBlockDetail))
            } else {
                ai.startGeneralSession(overview: cityWideOverview)
            }
        }
    }

    // MARK: - AI grounding

    /// Real aggregate stats across whatever's currently loaded — used to ground
    /// the AI before any specific block is selected.
    private var cityWideOverview: String {
        guard !allBlocks.isEmpty else { return "No block data has loaded yet." }
        let avgVacancy = allBlocks.map(\.vacancyRatePct).reduce(0, +) / Double(allBlocks.count)
        let sensorCovered = allBlocks.filter { $0.pedestrianSensorsCount > 0 }.count
        let busiest = allBlocks.max { $0.activeEstablishments < $1.activeEstablishments }

        var lines: [String] = []
        lines.append("Blocks loaded: \(allBlocks.count) across Greater Melbourne.")
        lines.append("Average vacancy rate across loaded blocks: \(String(format: "%.1f", avgVacancy))%.")
        lines.append("Blocks with real pedestrian sensor coverage: \(sensorCovered) of \(allBlocks.count).")
        if let busiest {
            lines.append("Busiest block by active business count: Block \(busiest.blockId) (\(busiest.clueSmallArea)) with \(busiest.activeEstablishments) active businesses.")
        }
        lines.append("Full detailed business lists (exact names/addresses) are only available for Block 25 and Block 804 — everywhere else is summary-level only.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Top nav (mirrors LandingView exactly)

    private var topNav: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(AppColor.tealAccent).frame(width: 8, height: 8)
                Text("iLoca")
                    .font(AppFont.headline(20))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 28) {
                ForEach(["How It Works", "About", "Home", "Map", "Guide"], id: \.self) { item in
                    Text(item)
                        .font(AppFont.nav(14, weight: item == activeTab ? .semibold : .regular))
                        .foregroundStyle(item == activeTab ? AppColor.mintLight : AppColor.mutedGrey)
                        .contentShape(Rectangle())
                        .onTapGesture { onNavTap?(item) }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AppColor.navyBackground)
    }

    // MARK: - Map

    private var mapArea: some View {
        Map(position: $cameraPosition) {
            ForEach(visibleBlocks, id: \.blockId) { block in
                Annotation("Block \(block.blockId)", coordinate: coordinateFor(block)) {
                    pin(for: block)
                }

                if filters.showFootfallZones {
                    MapCircle(center: coordinateFor(block), radius: footfallZoneRadius(for: block))
                        .foregroundStyle(footfallTier(for: block).zoneColor.opacity(0.35))
                        .stroke(footfallTier(for: block).zoneColor.opacity(0.8), lineWidth: 1)
                }

                if filters.showVacancyZones {
                    MapCircle(center: coordinateFor(block), radius: vacancyZoneRadius(for: block))
                        .foregroundStyle(vacancyZoneColor(for: block).opacity(0.35))
                        .stroke(vacancyZoneColor(for: block).opacity(0.8), lineWidth: 1)
                }
            }

            // Competitor markers: a distinct ring style so they read as
            // "nearby rivals" rather than ordinary blocks.
            ForEach(competitorBlocks, id: \.blockId) { block in
                Annotation("", coordinate: coordinateFor(block)) {
                    Circle()
                        .strokeBorder(AppColor.scoreGood, lineWidth: 2)
                        .background(Circle().fill(AppColor.scoreGood.opacity(0.25)))
                        .frame(width: 16, height: 16)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: poiFilter))
        .overlay(alignment: .topLeading) {
            breadcrumb
        }
    }

    private func footfallZoneRadius(for block: BlockSummary) -> CLLocationDistance {
        switch footfallTier(for: block) {
        case .any, .low: return 60
        case .medium: return 100
        case .high: return 150
        case .veryHigh: return 200
        }
    }

    // Dot size scales directly with real vacancy rate: 0% vacancy -> a small
    // 30m dot, 100% vacancy -> a 220m dot. Linear, so the size difference is
    // an honest read of the actual number, not a stylized bucket.
    private func vacancyZoneRadius(for block: BlockSummary) -> CLLocationDistance {
        let clamped = min(max(block.vacancyRatePct, 0), 100)
        return 30 + (clamped / 100) * 190
    }

    private func vacancyZoneColor(for block: BlockSummary) -> Color {
        if block.vacancyRatePct > 25 { return AppColor.scorePoor }
        if block.vacancyRatePct > 12 { return AppColor.scoreModerate }
        return AppColor.scoreExcellent
    }

    private func coordinateFor(_ block: BlockSummary) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: block.centroidLat, longitude: block.centroidLon)
    }

    // Default pin styling is deliberately understated — small, muted-opacity —
    // so nothing reads as "highlighted" before the user taps anything. Only an
    // actual selection gets the larger size + glow.
    @ViewBuilder
    private func pin(for block: BlockSummary) -> some View {
        let score = OpportunityScore.compute(for: block, maxActiveEstablishments: maxActiveEstablishments)
        let isSelected = block.blockId == selectedBlockId
        let isDimmed = selectedBlockId != nil && !isSelected

        Image(systemName: isSelected ? "mappin.circle.fill" : "circle.fill")
            .font(.system(size: isSelected ? 28 : 10))
            .foregroundStyle(score.tier.color)
            .shadow(color: score.tier.color.opacity(isSelected ? 0.7 : 0), radius: isSelected ? 8 : 0)
            .opacity(isDimmed ? 0.3 : (isSelected ? 1 : 0.8))
            .contentShape(Circle())
            .onTapGesture {
                selectedBlockId = (selectedBlockId == block.blockId) ? nil : block.blockId
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text("Greater Melbourne")
            Text(">").foregroundStyle(AppColor.mutedGrey)
            Text("Melbourne")
            if let block = selectedBlock {
                Text(">").foregroundStyle(AppColor.mutedGrey)
                Text("Block \(block.blockId)").foregroundStyle(AppColor.tealAccent)
            }
        }
        .font(AppFont.nav(13, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppColor.panelSurface.opacity(0.9))
        .clipShape(Capsule())
        .padding(16)
    }

    // MARK: - Selection behavior

    private func loadDetailIfAvailable(for blockId: Int?) {
        switch blockId {
        case 25: selectedBlockDetail = DataLoader.loadBlock25Detail()
        case 804: selectedBlockDetail = DataLoader.loadBlock804Detail()
        default: selectedBlockDetail = nil
        }
    }

    private func flyToSelectedBlock() {
        guard let block = selectedBlock else { return }
        let coord = coordinateFor(block)
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .camera(
                MapCamera(centerCoordinate: coord, distance: 900, heading: 0, pitch: 55)
            )
        }
    }
}

private extension FootfallLevel {
    var zoneColor: Color {
        switch self {
        case .any, .low: return AppColor.scorePoor
        case .medium: return AppColor.scoreModerate
        case .high: return AppColor.scoreGood
        case .veryHigh: return AppColor.scoreExcellent
        }
    }
}

#Preview {
    ContentView(activeTab: .constant("Map"), currentBlockLabel: .constant(nil), ai: LocationAdvisorAI())
        .frame(width: 1400, height: 900)
}
