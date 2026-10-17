import SwiftUI

struct MapSidebar: View {
    let store: CityDataStore
    @Bindable var filters: MapFilterState

    @State private var blockSearch = ""
    @State private var expanded: Set<String> = ["business", "location", "footfall", "competition"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                resultsHeader

                divider

                section("BUSINESS TYPE", key: "business") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(BusinessCategory.allCases) { category in
                                categoryButton(category)
                            }
                        }
                        Text(filters.businessCategory == nil
                             ? "Pick what you plan to open. Competition filters and rival lists will use it."
                             : "Competition is measured against other \(filters.businessCategory!.rawValue) businesses.")
                            .font(AppFont.nav(11))
                            .foregroundStyle(AppColor.mutedGrey)
                    }
                }

                divider

                section("LOCATION", key: "location") {
                    VStack(alignment: .leading, spacing: 14) {
                        areaPicker
                        blockPicker
                    }
                }

                divider

                section("FOOTFALL", key: "footfall") {
                    VStack(alignment: .leading, spacing: 16) {
                        pillGroupLabel("Time of Day")
                        FlowLayout(spacing: 8) {
                            ForEach(TimeOfDay.allCases) { time in
                                pill(time.rawValue, isOn: filters.timesOfDay.contains(time)) {
                                    if filters.timesOfDay.contains(time) { filters.timesOfDay.remove(time) } else { filters.timesOfDay.insert(time) }
                                }
                                .help(time.label)
                            }
                        }

                        pillGroupLabel("Day Type")
                        FlowLayout(spacing: 8) {
                            ForEach(DayType.allCases) { day in
                                pill(day.rawValue, isOn: filters.dayTypes.contains(day)) {
                                    if filters.dayTypes.contains(day) { filters.dayTypes.remove(day) } else { filters.dayTypes.insert(day) }
                                }
                            }
                        }

                        pillGroupLabel("Level")
                        pillWrap(FootfallLevel.allCases, selection: $filters.footfallLevel)

                        note("Uses real pedestrian sensor averages for \(filters.timeWindowLabel). Levels are quarters of measured blocks, and blocks without a sensor are hidden when a level is chosen.")
                    }
                }

                divider

                section("COMPETITION", key: "competition") {
                    VStack(alignment: .leading, spacing: 16) {
                        pillGroupLabel("Competitor Type")
                        pillWrap(CompetitorType.allCases, selection: $filters.competitorType)

                        pillGroupLabel("Search Radius")
                        FlowLayout(spacing: 8) {
                            ForEach(SearchRadius.allCases) { radius in
                                pill(radius.label, isOn: filters.searchRadius == radius) {
                                    filters.searchRadius = radius
                                }
                            }
                        }

                        pillGroupLabel("Competition Preference")
                        pillWrap(CompetitionPreference.allCases, selection: $filters.competitionPreference)

                        note("Counts \(filters.competitorType.rawValue.lowercased())\(filters.businessCategory == nil ? "" : " (\(filters.businessCategory!.rawValue))") within \(filters.searchRadius.label) of each block. Low, balanced and established are the bottom, middle and top thirds of all blocks.")
                    }
                }

                divider

                section("MAP OVERLAYS", key: "overlays") {
                    VStack(spacing: 14) {
                        overlayToggle("Competitor Markers", isOn: $filters.showCompetitorMarkers,
                                      hint: "Nearby blocks with competitors, around the selected block")
                        overlayToggle("Business Locations", isOn: $filters.showBusinessDots,
                                      hint: "Each business and vacancy in the selected block")
                        overlayToggle("Footfall Zones", isOn: $filters.showFootfallZones,
                                      hint: "Pedestrian sensors, sized by people per hour")
                        overlayToggle("Vacancy", isOn: $filters.showVacancyZones,
                                      hint: "Bigger circle = more empty shopfronts")
                        overlayToggle("Public Car Parks", isOn: $filters.showCarParks,
                                      hint: "Commercial off-street car parks, sized by spaces")
                        overlayToggle("Live On-street Parking", isOn: $filters.showOnStreetParking,
                                      hint: store.onStreet?.latestReport.map { "Sensor bays, free vs occupied · \(MelbourneTime.time($0))" }
                                        ?? "Sensor bays, free vs occupied, refreshed every 5 min")
                    }
                }

                divider

                section("SCORE SCALE", key: "score") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(OpportunityTier.allCases, id: \.self) { tier in
                            HStack(spacing: 10) {
                                Circle().fill(tier.color).frame(width: 9, height: 9)
                                Text(tier.range)
                                    .font(AppFont.mono(12))
                                    .foregroundStyle(AppColor.mutedGrey)
                                Text(tier.rawValue)
                                    .font(AppFont.nav(13))
                                    .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                            }
                        }
                        note("Hollow pins have Low data confidence. See the Info tab for how scores are calculated.")
                    }
                }

                divider

                section("COMING SOON", key: "soon", collapsible: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        comingSoonRow("Rental Listings")
                        comingSoonRow("Multi-location compare")
                    }
                }
            }
            .padding(18)
        }
        .background(AppColor.navyBackground)
    }

    // MARK: - Results header

    private var resultsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.visibleBlocks.count) of \(store.blocks.count) blocks")
                    .font(AppFont.nav(14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(filters.timeWindowLabel)
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
            }
            Spacer()
            if filters.isFiltering || filters.businessCategory != nil || !filters.timesOfDay.isEmpty || !filters.dayTypes.isEmpty {
                Button("Reset") { filters.resetAll() }
                    .buttonStyle(.plain)
                    .font(AppFont.nav(12, weight: .semibold))
                    .foregroundStyle(AppColor.tealAccent)
            }
        }
    }

    // MARK: - Location

    private var areaPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Area")
                .font(AppFont.nav(13))
                .foregroundStyle(AppColor.mutedGrey)
            Menu {
                Button("All areas") { filters.area = nil }
                Divider()
                ForEach(store.areas, id: \.self) { area in
                    Button(area) { filters.area = area }
                }
            } label: {
                HStack {
                    Text(filters.area ?? "All areas")
                        .font(AppFont.nav(14))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.mutedGrey)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppColor.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    /// Search by block number or area; otherwise the top-scoring visible blocks.
    private var listedBlocks: [CityBlock] {
        let query = blockSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = query.isEmpty ? store.visibleBlocks : store.blocks.filter {
            String($0.blockId).hasPrefix(query) || $0.area.lowercased().contains(query)
        }
        return pool
            .sorted { (store.score(for: $0)?.value ?? 0) > (store.score(for: $1)?.value ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    private var blockPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(blockSearch.isEmpty ? "Top blocks" : "Matching blocks")
                    .font(AppFont.nav(13))
                    .foregroundStyle(AppColor.mutedGrey)
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(AppColor.mutedGrey)
                TextField("Block number or area", text: $blockSearch)
                    .textFieldStyle(.plain)
                    .font(AppFont.nav(13))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 0) {
                if listedBlocks.isEmpty {
                    Text(store.source == .loading ? "Loading blocks…" : "No blocks match")
                        .font(AppFont.nav(12))
                        .foregroundStyle(AppColor.mutedGrey)
                        .padding(12)
                }
                ForEach(listedBlocks) { block in
                    blockRow(block)
                }
            }
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
        }
    }

    private func blockRow(_ block: CityBlock) -> some View {
        let score = store.score(for: block)
        return HStack(spacing: 10) {
            Circle().fill(score?.tier.color ?? AppColor.mutedGrey).frame(width: 8, height: 8)
            Text(verbatim: "Block \(block.blockId)")
                .font(AppFont.nav(13, weight: .semibold))
            Text(block.area)
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.mutedGrey)
                .lineLimit(1)
            Spacer()
            Text(score.map { "\($0.value)" } ?? "–")
                .font(AppFont.mono(12, weight: .semibold))
                .foregroundStyle(score?.tier.color ?? AppColor.mutedGrey)
        }
        .foregroundStyle(AppColor.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(store.selectedBlockId == block.blockId ? AppColor.tealAccent.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedBlockId = block.blockId }
    }

    // MARK: - Business type

    private func categoryButton(_ category: BusinessCategory) -> some View {
        let isSelected = filters.businessCategory == category
        return VStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: 18))
            Text(category.rawValue)
                .font(AppFont.nav(13, weight: .semibold))
        }
        .foregroundStyle(isSelected ? AppColor.tealAccent : AppColor.textPrimary.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isSelected ? AppColor.tealAccent.opacity(0.12) : AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? AppColor.tealAccent : AppColor.cardBorder, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            filters.businessCategory = isSelected ? nil : category
        }
    }

    // MARK: - Generic pill controls

    private func pillGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.nav(12))
            .foregroundStyle(AppColor.mutedGrey)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppFont.nav(11))
            .foregroundStyle(AppColor.mutedGrey)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pillWrap<T: Identifiable & RawRepresentable>(_ items: [T], selection: Binding<T>) -> some View where T.RawValue == String {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                pill(item.rawValue, isOn: selection.wrappedValue.id == item.id) {
                    selection.wrappedValue = item
                }
            }
        }
    }

    private func pill(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(AppFont.nav(13, weight: .semibold))
            .foregroundStyle(isOn ? AppColor.navyBackground : AppColor.textPrimary.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isOn ? AppColor.tealAccent : AppColor.cardSurface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isOn ? .clear : AppColor.cardBorder, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }

    // MARK: - Overlays

    private func overlayToggle(_ label: String, isOn: Binding<Bool>, hint: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.nav(14))
                    .foregroundStyle(AppColor.textPrimary.opacity(0.9))
                Text(hint)
                    .font(AppFont.nav(10))
                    .foregroundStyle(AppColor.mutedGrey)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(AppColor.tealAccent)
                .labelsHidden()
        }
    }

    private func comingSoonRow(_ label: String) -> some View {
        HStack {
            Circle().fill(AppColor.mutedGrey.opacity(0.5)).frame(width: 5, height: 5)
            Text(label)
                .font(AppFont.nav(13))
                .foregroundStyle(AppColor.mutedGrey)
            Spacer()
            Text("soon")
                .font(AppFont.mono(11))
                .foregroundStyle(AppColor.tealAccent.opacity(0.7))
        }
    }

    // MARK: - Section shell

    private var divider: some View {
        Divider().overlay(AppColor.cardBorder).padding(.vertical, 16)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, key: String, collapsible: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(AppFont.mono(12, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(AppColor.textPrimary.opacity(0.9))
                Spacer()
                if collapsible {
                    Image(systemName: expanded.contains(key) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.mutedGrey)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard collapsible else { return }
                if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
            }

            if !collapsible || expanded.contains(key) {
                content()
            }
        }
    }
}

/// Minimal flow layout so filter pills wrap naturally instead of overflowing
/// or being squeezed into a fixed grid.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
