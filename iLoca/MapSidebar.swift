import SwiftUI

struct MapSidebar: View {
    let allBlocks: [BlockSummary]
    @Binding var selectedBlockId: Int?
    @Bindable var filters: MapFilterState

    /// Block 25 and 804 are always pinned at the top and are the only clickable
    /// rows (they're the only blocks with full detailed business data). The next
    /// 8 are picked at runtime by highest active-business count, so this list
    /// stays accurate without hardcoding specific block IDs.
    private var pinnedBlocks: [BlockSummary] {
        allBlocks.filter { $0.blockId == 25 || $0.blockId == 804 }
            .sorted { $0.blockId == 25 && $1.blockId != 25 }
    }

    private var extraBlocks: [BlockSummary] {
        allBlocks
            .filter { $0.blockId != 25 && $0.blockId != 804 }
            .sorted { $0.activeEstablishments > $1.activeEstablishments }
            .prefix(8)
            .map { $0 }
    }

    @State private var expanded: Set<String> = ["business", "location", "vacancy"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("BUSINESS TYPE", key: "business") {
                    HStack(spacing: 10) {
                        ForEach(BusinessCategory.allCases) { category in
                            categoryButton(category)
                        }
                    }
                }

                divider

                section("LOCATION", key: "location") {
                    VStack(alignment: .leading, spacing: 14) {
                        labeledField("Region", value: "Greater Melbourne")
                        labeledField("City / LGA", value: "Melbourne")
                        blockPicker
                    }
                }

                divider

                section("VACANCY", key: "vacancy") {
                    VStack(spacing: 14) {
                        overlayToggle("Show Vacancy on Map", isOn: $filters.showVacancyZones)
                        Text("Dot size scales with each block's real vacancy rate — bigger dot, more empty shopfronts.")
                            .font(AppFont.nav(11))
                            .foregroundStyle(AppColor.mutedGrey)
                    }
                }

                divider

                section("FOOTFALL", key: "footfall") {
                    VStack(alignment: .leading, spacing: 16) {
                        pillGroupLabel("Level")
                        pillWrap(FootfallLevel.allCases, selection: Binding(
                            get: { filters.footfallLevel },
                            set: { filters.footfallLevel = $0 }
                        ))

                        pillGroupLabel("Time of Day")
                        multiPillWrap(TimeOfDay.allCases, selection: $filters.timesOfDay)

                        pillGroupLabel("Day Type")
                        multiPillWrap(DayType.allCases, selection: $filters.dayTypes)
                    }
                }

                divider

                section("COMPETITION", key: "competition") {
                    VStack(alignment: .leading, spacing: 16) {
                        pillGroupLabel("Competitor Type")
                        pillWrap(CompetitorType.allCases, selection: Binding(
                            get: { filters.competitorType },
                            set: { filters.competitorType = $0 }
                        ))

                        pillGroupLabel("Search Radius")
                        FlowLayout(spacing: 8) {
                            ForEach(SearchRadius.allCases) { radius in
                                pill(radius.label, isOn: filters.searchRadius == radius) {
                                    filters.searchRadius = radius
                                }
                            }
                        }

                        pillGroupLabel("Competition Preference")
                        pillWrap(CompetitionPreference.allCases, selection: Binding(
                            get: { filters.competitionPreference },
                            set: { filters.competitionPreference = $0 }
                        ))
                    }
                }

                divider

                section("MAP OVERLAYS", key: "overlays") {
                    VStack(spacing: 14) {
                        overlayToggle("Competitor Markers", isOn: $filters.showCompetitorMarkers)
                        overlayToggle("Development Sites", isOn: $filters.showDevelopmentSites, isDummy: true)
                        overlayToggle("Transit Stops", isOn: $filters.showTransitStops, isDummy: true)
                        overlayToggle("Footfall Zones", isOn: $filters.showFootfallZones)
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
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }

                divider

                section("COMING SOON", key: "soon", collapsible: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        comingSoonRow("Rental Listings")
                        comingSoonRow("Cost Estimator")
                        comingSoonRow("Supplier Market")
                        comingSoonRow("Multi-location")
                    }
                }
            }
            .padding(18)
        }
        .background(AppColor.navyBackground)
    }

    // MARK: - Location / block picker

    private var blockPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Block")
                .font(AppFont.nav(13))
                .foregroundStyle(AppColor.mutedGrey)

            VStack(spacing: 0) {
                ForEach(pinnedBlocks, id: \.blockId) { block in
                    blockRow(block, clickable: true)
                }
                ForEach(extraBlocks, id: \.blockId) { block in
                    blockRow(block, clickable: false)
                }
            }
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
        }
    }

    private func blockRow(_ block: BlockSummary, clickable: Bool) -> some View {
        HStack {
            Text("Block \(block.blockId)")
                .font(AppFont.nav(13, weight: clickable ? .semibold : .regular))
            Spacer()
            Text(block.clueSmallArea)
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.mutedGrey)
                .lineLimit(1)
        }
        .foregroundStyle(clickable ? .white : AppColor.inactiveText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selectedBlockId == block.blockId ? AppColor.tealAccent.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard clickable else { return }
            selectedBlockId = block.blockId
        }
        .opacity(clickable ? 1 : 0.45)
    }

    private func labeledField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.nav(13))
                .foregroundStyle(AppColor.mutedGrey)
            Text(value)
                .font(AppFont.nav(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColor.cardBorder, lineWidth: 1))
        }
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
        .foregroundStyle(isSelected ? AppColor.tealAccent : .white.opacity(0.8))
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

    private func pillWrap<T: Identifiable & RawRepresentable>(_ items: [T], selection: Binding<T>) -> some View where T.RawValue == String {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                pill(item.rawValue, isOn: selection.wrappedValue.id == item.id) {
                    selection.wrappedValue = item
                }
            }
        }
    }

    private func multiPillWrap<T: Identifiable & RawRepresentable & Hashable>(_ items: [T], selection: Binding<Set<T>>) -> some View where T.RawValue == String {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                pill(item.rawValue, isOn: selection.wrappedValue.contains(item)) {
                    if selection.wrappedValue.contains(item) {
                        selection.wrappedValue.remove(item)
                    } else {
                        selection.wrappedValue.insert(item)
                    }
                }
            }
        }
    }

    private func pill(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Text(label)
            .font(AppFont.nav(13, weight: .semibold))
            .foregroundStyle(isOn ? AppColor.navyBackground : .white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isOn ? AppColor.tealAccent : AppColor.cardSurface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isOn ? .clear : AppColor.cardBorder, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
    }

    // MARK: - Overlays

    private func overlayToggle(_ label: String, isOn: Binding<Bool>, isDummy: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(AppFont.nav(14))
                .foregroundStyle(.white.opacity(0.9))
            if isDummy {
                Text("DEMO")
                    .font(AppFont.mono(9))
                    .foregroundStyle(AppColor.mutedGrey)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(AppColor.mutedGrey.opacity(0.5), lineWidth: 1))
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
                    .foregroundStyle(.white.opacity(0.9))
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
