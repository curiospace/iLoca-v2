import SwiftUI
import MapKit

struct ContentView: View {
    var onNavTap: ((AppPage) -> Void)? = nil
    let store: CityDataStore
    let ai: LocationAdvisorAI

    @State private var cameraPosition: MapCameraPosition = ContentView.cityCamera

    private var filters: MapFilterState { store.filters }

    var body: some View {
        VStack(spacing: 0) {
            TopNavBar(activePage: .map, onNavTap: onNavTap)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            Divider().overlay(AppColor.cardBorder)
            HStack(spacing: 0) {
                MapSidebar(store: store, filters: filters)
                    .frame(width: 300)

                Divider().overlay(AppColor.cardBorder)

                mapArea
                    .frame(maxWidth: .infinity)

                if let block = store.selectedBlock {
                    Divider().overlay(AppColor.cardBorder)
                    MapDetailPanel(block: block, store: store)
                        .frame(width: 360)
                }
            }
        }
        .background(AppColor.navyBackground)
        .onChange(of: store.selectedBlockId) { _, _ in
            flyToSelectedBlock()
            // A new block means a new conversation (ephemeral chats).
            ai.reground(store: store)
        }
        // Keep live parking current while the overlay is on.
        .task(id: filters.showOnStreetParking) {
            while filters.showOnStreetParking && !Task.isCancelled {
                await store.refreshOnStreetIfStale()
                try? await Task.sleep(for: .seconds(CityDataStore.onStreetRefreshInterval))
            }
        }
        .onAppear { if store.selectedBlockId == nil { cameraPosition = Self.cityCamera } }
    }

    /// Opening view: the CBD grid, tilted for the 3D buildings.
    static let cityCamera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9580),
                  distance: 4200, heading: 0, pitch: 45)
    )

    // MARK: - Map

    private var mapArea: some View {
        Map(position: $cameraPosition) {
            ForEach(store.visibleBlocks) { block in
                Annotation(String("Block \(block.blockId)"), coordinate: block.coordinate) {
                    pin(for: block)
                }

                if filters.showVacancyZones {
                    MapCircle(center: block.coordinate, radius: vacancyZoneRadius(for: block))
                        .foregroundStyle(vacancyZoneColor(for: block).opacity(0.3))
                        .stroke(vacancyZoneColor(for: block).opacity(0.8), lineWidth: 1)
                }
            }

            // Footfall zones: drawn at the real sensor positions, sized by people/hour
            // for the selected time window.
            if filters.showFootfallZones {
                ForEach(store.sensors) { sensor in
                    if let ff = CityDataStore.footfall(sensor: sensor, hours: filters.selectedHours, dayTypes: filters.dayTypes) {
                        MapCircle(center: sensor.coordinate, radius: footfallRadius(ff))
                            .foregroundStyle(AppColor.tealAccent.opacity(0.25))
                            .stroke(AppColor.tealAccent.opacity(0.8), lineWidth: 1)
                    }
                }
            }

            // Off-street public car parks (dataset 5), sized by capacity.
            if filters.showCarParks {
                ForEach(store.carParks) { park in
                    Annotation("", coordinate: park.coordinate, anchor: .center) {
                        let size = min(24, 12 + CGFloat(park.spaces).squareRoot() / 3)
                        Text("P")
                            .font(.system(size: size * 0.55, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: size, height: size)
                            .background(RoundedRectangle(cornerRadius: size * 0.25).fill(AppColor.gradientRoyalBlue))
                            .overlay(RoundedRectangle(cornerRadius: size * 0.25).stroke(.white.opacity(0.6), lineWidth: 1))
                            .help("\(park.address): \(park.spaces) public spaces")
                    }
                }
            }

            // Live on-street bays (dataset 6): individual bays around the selected
            // block, otherwise each block's share of free bays.
            if filters.showOnStreetParking {
                if let selected = store.selectedBlock {
                    ForEach(store.bays(around: selected)) { bay in
                        MapCircle(center: bay.coordinate, radius: 4)
                            .foregroundStyle((bay.isOccupied ? AppColor.scorePoor : AppColor.scoreExcellent).opacity(0.9))
                    }
                } else {
                    let occupancy = store.bayOccupancyByBlock()
                    ForEach(store.blocks.filter { occupancy[$0.blockId] != nil }) { block in
                        let entry = occupancy[block.blockId]!
                        MapCircle(center: block.coordinate, radius: min(120, 25 + Double(entry.total) * 2.5))
                            .foregroundStyle(MapDetailPanel.freeColor(Double(entry.free) / Double(entry.total)).opacity(0.3))
                            .stroke(MapDetailPanel.freeColor(Double(entry.free) / Double(entry.total)).opacity(0.85), lineWidth: 1)
                    }
                }
            }

            if let selected = store.selectedBlock {
                if filters.showCompetitorMarkers {
                    MapCircle(center: selected.coordinate, radius: CLLocationDistance(filters.searchRadius.rawValue))
                        .foregroundStyle(AppColor.scoreGood.opacity(0.06))
                        .stroke(AppColor.scoreGood.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(store.competitorBlocks(around: selected), id: \.block.blockId) { item in
                        Annotation("", coordinate: item.block.coordinate) {
                            Text("\(item.count)")
                                .font(AppFont.mono(9, weight: .bold))
                                .foregroundStyle(AppColor.textPrimary)
                                .frame(width: competitorSize(item.count), height: competitorSize(item.count))
                                .background(Circle().fill(AppColor.scoreGood.opacity(0.35)))
                                .overlay(Circle().strokeBorder(AppColor.scoreGood, lineWidth: 1.5))
                                .help("Block \(item.block.blockId): \(item.count) \(filters.competitorType.rawValue.lowercased())")
                                .onTapGesture { store.selectedBlockId = item.block.blockId }
                        }
                    }
                }

                // Dataset 3 point locations for each business / vacancy in the block.
                if filters.showBusinessDots, let premises = store.premisesByBlock[selected.blockId] {
                    ForEach(businessDots(premises), id: \.id) { dot in
                        Annotation("", coordinate: dot.coordinate, anchor: .center) {
                            let size = min(26, 9 + CGFloat(dot.count).squareRoot() * 2.2)
                            Circle()
                                .fill(dot.color.opacity(0.9))
                                .frame(width: size, height: size)
                                .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 0.75))
                                .overlay {
                                    if dot.count > 1 {
                                        Text(verbatim: "\(dot.count)")
                                            .font(AppFont.mono(8, weight: .bold))
                                            .foregroundStyle(.black.opacity(0.75))
                                    }
                                }
                                .help(dot.label)
                        }
                    }
                }
            }
        }
        // Only iLoca's own City of Melbourne data is shown, not Apple Maps business labels.
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .overlay(alignment: .topLeading) { breadcrumb }
        .overlay(alignment: .bottomLeading) { mapLegend }
        .overlay { loadingOverlay }
    }

    // Businesses in one building share coordinates, so they're drawn as one dot per
    // building: coloured by its most common type (grey if all vacant), sized by count.
    private struct BusinessDot { let id: String; let coordinate: CLLocationCoordinate2D; let color: Color; let count: Int; let label: String }

    private func businessDots(_ premises: [BusinessRecord]) -> [BusinessDot] {
        let located = premises.filter { $0.coordinate != nil }
        let grouped = Dictionary(grouping: located) { "\($0.latitude!)|\($0.longitude!)" }
        return grouped.map { key, group in
            let categories = group.compactMap(\.category)
            let dominant = Dictionary(grouping: categories, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            let vacant = group.filter(\.isVacant).count
            let names = group.filter { !$0.isVacant }.prefix(6).map(\.name).joined(separator: ", ")
            var label = "\(group.count) premises: \(names)"
            if group.count - vacant > 6 { label += "…" }
            if vacant > 0 { label += " (\(vacant) vacant)" }
            return BusinessDot(id: key, coordinate: group[0].coordinate!,
                               color: dominant?.color ?? AppColor.mutedGrey,
                               count: group.count, label: label)
        }
    }

    private func competitorSize(_ count: Int) -> CGFloat {
        min(34, 16 + CGFloat(count).squareRoot() * 2.5)
    }

    private func footfallRadius(_ perHour: Double) -> CLLocationDistance {
        min(220, 25 + perHour.squareRoot() * 4)
    }

    // Circle size scales with vacancy rate: 0% -> 30 m, 100% -> 220 m.
    private func vacancyZoneRadius(for block: CityBlock) -> CLLocationDistance {
        let clamped = min(max(block.vacancyRatePct, 0), 100)
        return 30 + (clamped / 100) * 190
    }

    private func vacancyZoneColor(for block: CityBlock) -> Color {
        if block.vacancyRatePct > 25 { return AppColor.scorePoor }
        if block.vacancyRatePct > 12 { return AppColor.scoreModerate }
        return AppColor.scoreExcellent
    }

    // Default pins are small and muted so nothing reads as "highlighted" before a
    // tap. Low-confidence blocks are drawn hollow so weak data is visible at a glance.
    @ViewBuilder
    private func pin(for block: CityBlock) -> some View {
        let color = store.score(for: block)?.tier.color ?? AppColor.mutedGrey
        let isSelected = block.blockId == store.selectedBlockId
        let isDimmed = store.selectedBlockId != nil && !isSelected
        let lowConfidence = store.confidence(for: block).level == .low

        Image(systemName: isSelected ? "mappin.circle.fill" : (lowConfidence ? "circle" : "circle.fill"))
            .font(.system(size: isSelected ? 28 : 10, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: color.opacity(isSelected ? 0.7 : 0), radius: isSelected ? 8 : 0)
            .opacity(isDimmed ? 0.3 : (isSelected ? 1 : 0.85))
            .contentShape(Circle())
            .onTapGesture {
                store.selectedBlockId = (store.selectedBlockId == block.blockId) ? nil : block.blockId
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text("City of Melbourne")
                .onTapGesture {
                    store.selectedBlockId = nil
                    withAnimation(.easeInOut(duration: 0.8)) { cameraPosition = Self.cityCamera }
                }
            if let area = store.selectedBlock?.area ?? filters.area {
                Text(">").foregroundStyle(AppColor.mutedGrey)
                Text(area)
            }
            if let block = store.selectedBlock {
                Text(">").foregroundStyle(AppColor.mutedGrey)
                Text(verbatim: "Block \(block.blockId)").foregroundStyle(AppColor.tealAccent)
            }
        }
        .font(AppFont.nav(13, weight: .medium))
        .foregroundStyle(AppColor.textPrimary.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppColor.panelSurface.opacity(0.9))
        .clipShape(Capsule())
        .padding(16)
    }

    @ViewBuilder
    private var mapLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            if filters.showOnStreetParking || filters.showCarParks {
                HStack(spacing: 12) {
                    if filters.showCarParks {
                        HStack(spacing: 5) {
                            Text("P").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 12, height: 12)
                                .background(RoundedRectangle(cornerRadius: 3).fill(AppColor.gradientRoyalBlue))
                            Text("Public car park").font(AppFont.nav(11)).foregroundStyle(AppColor.textPrimary.opacity(0.85))
                        }
                    }
                    if filters.showOnStreetParking {
                        legendDot(AppColor.scoreExcellent, store.selectedBlock == nil ? "Mostly free" : "Free bay")
                        legendDot(AppColor.scorePoor, store.selectedBlock == nil ? "Mostly taken" : "Occupied")
                        if store.onStreetLoading { ProgressView().controlSize(.mini) }
                        else if let report = store.onStreet?.latestReport {
                            Text("live · \(MelbourneTime.time(report))")
                                .font(AppFont.mono(10)).foregroundStyle(AppColor.mutedGrey)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppColor.panelSurface.opacity(0.9))
                .clipShape(Capsule())
            }
            if store.selectedBlock != nil && filters.showBusinessDots {
                HStack(spacing: 12) {
                    ForEach(BusinessCategory.allCases) { c in
                        legendDot(c.color, c.rawValue)
                    }
                    legendDot(AppColor.mutedGrey, "Vacant")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppColor.panelSurface.opacity(0.9))
                .clipShape(Capsule())
            }
        }
        .padding(16)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(AppFont.nav(11)).foregroundStyle(AppColor.textPrimary.opacity(0.85))
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        switch store.source {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading live City of Melbourne data…")
                    .font(AppFont.nav(13))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(20)
            .background(AppColor.panelSurface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        case .unavailable(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(AppColor.scorePoor)
                Text("Couldn't load City of Melbourne data")
                    .font(AppFont.nav(14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Try again") { Task { await store.load() } }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.tealAccent)
            }
            .padding(20)
            .background(AppColor.panelSurface.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        default:
            EmptyView()
        }
    }

    // MARK: - Selection behaviour

    private func flyToSelectedBlock() {
        guard let block = store.selectedBlock else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .camera(
                MapCamera(centerCoordinate: block.coordinate, distance: 900, heading: 0, pitch: 55)
            )
        }
    }
}
