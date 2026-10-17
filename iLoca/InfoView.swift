import SwiftUI

/// The Info page, laid out as a dashboard: headline tiles, the selected block's
/// score and confidence at a glance, how it all works as small visuals, data
/// sources, and trust & privacy. The full methodology text is still available
/// in a collapsed section at the bottom. The assistant on the right answers
/// questions about any of it.
struct InfoView: View {
    var onNavTap: ((AppPage) -> Void)? = nil
    let store: CityDataStore

    @State private var infoAI = InfoAdvisorAI()
    @State private var ai = LocaAI.shared
    @State private var showMethodology = false
    @Environment(\.reportIssue) private var reportIssue

    private var block: CityBlock? { store.selectedBlock }

    var body: some View {
        ZStack {
            ParticleBackgroundView()

            VStack(spacing: 0) {
                TopNavBar(activePage: .info, onNavTap: onNavTap)
                    .padding(.top, 22)
                    .padding(.horizontal, 40)

                header
                    .padding(.horizontal, 40)
                    .padding(.top, 18)

                HStack(alignment: .top, spacing: 24) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            kpiRow
                            blockSection
                            howItWorks
                            dataSources
                            trustAndPrivacy
                            methodology
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity)

                    LocaChatPanel(
                        title: "Loca · Ask about iLoca",
                        subtitle: block.map { "Block \($0.blockId) selected" } ?? "Scores, data, privacy",
                        session: infoAI.session,
                        emptyTitle: "Ask how scores, confidence or the data work",
                        suggestions: infoSuggestions,
                        placeholder: "Ask how iLoca works…",
                        onAsk: { question in
                            infoAI.ground(store: store)
                            infoAI.session.ask(question)
                        }
                    )
                    .frame(width: 380)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
            }
        }
        .onAppear { infoAI.ground(store: store) }
        .onChange(of: store.selectedBlockId) { _, _ in infoAI.ground(store: store) }
    }

    private var infoSuggestions: [String] {
        var list = [
            "How is the Opportunity Score calculated?",
            "What does the confidence level mean?",
            "How fresh is the data?",
            "What gets sent to Claude?"
        ]
        if let block { list.insert("Why is Block \(block.blockId)'s confidence what it is?", at: 0) }
        return list
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TRANSPARENCY")
                    .font(AppFont.mono(12, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(AppColor.mintLight)
                Text("HOW LOCA DECIDED")
                    .font(AppFont.headline(36))
                    .tracking(-0.5)
                    .foregroundStyle(AppColor.headlineGradient)
            }
            Spacer()
            Button {
                reportIssue(IssueContext(
                    blockId: block?.blockId,
                    blockArea: block?.area,
                    score: block.flatMap { store.score(for: $0)?.value },
                    confidence: block.map { store.confidence(for: $0).level.rawValue },
                    provider: ai.provider.displayName,
                    dataFreshness: store.freshnessLine
                ))
            } label: {
                Label("Report an issue", systemImage: "flag.fill")
                    .font(AppFont.nav(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColor.scorePoor.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Flag incorrect data, a misleading recommendation or unexpected AI behaviour")
        }
    }

    // MARK: - KPI tiles

    private var kpiRow: some View {
        let score = block.flatMap { store.score(for: $0) }
        let confidence = block.map { store.confidence(for: $0) }
        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                kpiTile(
                    title: "Opportunity Score",
                    icon: "gauge.with.dots.needle.50percent",
                    value: score.map { "\($0.value)" } ?? "–",
                    suffix: score == nil ? nil : "/ 100",
                    status: score.map { (color: $0.tier.color, icon: "circle.fill", label: $0.tier.rawValue) },
                    caption: block.map { "Block \($0.blockId) · \($0.area)" } ?? "Select a block on the Map"
                )
                kpiTile(
                    title: "Confidence",
                    icon: "checkmark.seal",
                    value: confidence.map { "\($0.points)" } ?? "–",
                    suffix: confidence == nil ? nil : "/ 100",
                    status: confidence.map { (color: $0.level.color, icon: $0.level.icon, label: $0.level.rawValue) },
                    caption: confidence?.summary ?? "How well the data backs the score"
                )
                kpiTile(
                    title: "City data",
                    icon: "externaldrive.connected.to.line.below",
                    value: dataValue,
                    suffix: nil,
                    status: dataStatus,
                    caption: dataCaption
                )
                kpiTile(
                    title: "AI assistant",
                    icon: "sparkles",
                    value: aiValue,
                    suffix: nil,
                    status: ai.provider.isAvailable
                        ? (color: AppColor.scoreExcellent, icon: "checkmark.circle.fill", label: "Ready")
                        : (color: AppColor.scorePoor, icon: "xmark.circle.fill", label: "Unavailable"),
                    caption: aiCaption
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dataValue: String {
        switch store.source {
        case .live: return "Live"
        case .cached: return "Offline"
        case .loading: return "Loading"
        case .unavailable: return "Offline"
        }
    }

    private var dataStatus: (color: Color, icon: String, label: String) {
        switch store.source {
        case .live(let at): return (AppColor.scoreExcellent, "dot.radiowaves.left.and.right", "Updated \(at.formatted(date: .omitted, time: .shortened))")
        case .cached(let at, _): return (AppColor.scoreModerate, "externaldrive", "Saved copy, \(at.formatted(.relative(presentation: .named)))")
        case .loading: return (AppColor.mutedGrey, "arrow.triangle.2.circlepath", "Fetching…")
        case .unavailable: return (AppColor.scorePoor, "exclamationmark.triangle.fill", "Couldn't load")
        }
    }

    private var dataCaption: String {
        var parts: [String] = []
        if store.censusYear > 0 { parts.append("\(store.censusYear) business census") }
        if let end = store.snapshot?.footfallWindowEnd { parts.append("foot traffic to \(MelbourneTime.shortDay(end))") }
        return parts.isEmpty ? "City of Melbourne Open Data" : parts.joined(separator: " · ").capitalizedFirst
    }

    private var aiValue: String {
        switch ai.provider {
        case .claude: return "Claude"
        case .onDevice: return "On-device"
        case .unavailable: return "Off"
        }
    }

    private var aiCaption: String {
        switch ai.provider {
        case .claude: return ClaudeClient.model
        case .onDevice: return "Apple model. Set ANTHROPIC_API_KEY in Xcode to use Claude."
        case .unavailable(let reason): return reason
        }
    }

    private func kpiTile(title: String, icon: String, value: String, suffix: String?,
                         status: (color: Color, icon: String, label: String)?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: icon)
                .font(AppFont.mono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AppColor.mutedGrey)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(AppFont.headline(30))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let suffix {
                    Text(suffix)
                        .font(AppFont.nav(12))
                        .foregroundStyle(AppColor.mutedGrey)
                }
            }
            if let status {
                Label(status.label, systemImage: status.icon)
                    .font(AppFont.nav(12, weight: .semibold))
                    .foregroundStyle(status.color)
                    .labelStyle(StatusLabelStyle(color: status.color))
                    .lineLimit(1)
            }
            Text(caption)
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.mutedGrey)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.cardBorder, lineWidth: 1))
    }

    // MARK: - Selected block

    @ViewBuilder
    private var blockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(block.map { "BLOCK \($0.blockId) AT A GLANCE" } ?? "YOUR BLOCK AT A GLANCE",
                         icon: "mappin.circle",
                         trailing: block.map { _ in "\(store.filters.timeWindowLabel)\(store.filters.businessCategory.map { " · \($0.rawValue)" } ?? "")" })

            if let block, let score = store.score(for: block) {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        scoreBreakdownCard(score)
                        confidenceChecklistCard(store.confidence(for: block))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .id(block.blockId)
            } else {
                card {
                    HStack(spacing: 14) {
                        Image(systemName: "map").font(.title2).foregroundStyle(AppColor.tealAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No block selected")
                                .font(AppFont.nav(14, weight: .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text("Pick a block on the Map to see what drives its score.")
                                .font(AppFont.nav(12))
                                .foregroundStyle(AppColor.mutedGrey)
                        }
                        Spacer()
                        Button("Open Map") { onNavTap?(.map) }
                            .buttonStyle(.plain)
                            .font(AppFont.nav(12, weight: .semibold))
                            .foregroundStyle(AppColor.tealAccent)
                    }
                }
            }
        }
    }

    private func scoreBreakdownCard(_ score: OpportunityScore) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("What makes up the score")
                ScoreMeter(score: score.value)
                ForEach(score.components) { c in
                    factorRow(c)
                }
            }
        }
    }

    private func factorRow(_ c: ScoreComponent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.kind.rawValue)
                    .font(AppFont.nav(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary.opacity(c.isMissing ? 0.5 : 1))
                Text("\(Int((c.appliedWeight * 100).rounded()))%")
                    .font(AppFont.mono(10, weight: .semibold))
                    .foregroundStyle(AppColor.mutedGrey)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(AppColor.textPrimary.opacity(0.06)))
                    .help("Weight in the score")
                Spacer()
                Text(c.value.map { _ in "+\(Int(c.contribution.rounded())) pts" } ?? "left out")
                    .font(AppFont.mono(11, weight: .semibold))
                    .foregroundStyle(c.isMissing ? AppColor.mutedGrey : AppColor.textPrimary)
            }
            Bar(fraction: (c.value ?? 0) / 100, color: AppColor.gradientTeal)
            Text(c.short)
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.mutedGrey)
        }
        .help(c.detail)
    }

    private func confidenceChecklistCard(_ confidence: ConfidenceAssessment) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Why this confidence level")
                HStack(spacing: 10) {
                    Label(confidence.level.rawValue, systemImage: confidence.level.icon)
                        .font(AppFont.nav(15, weight: .semibold))
                        .foregroundStyle(confidence.level.color)
                    Text("\(confidence.points) / 100")
                        .font(AppFont.mono(12, weight: .semibold))
                        .foregroundStyle(AppColor.mutedGrey)
                    Spacer()
                }
                ForEach(confidence.factors) { f in
                    HStack(spacing: 10) {
                        Image(systemName: checkIcon(f))
                            .font(.system(size: 14))
                            .foregroundStyle(checkColor(f))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name)
                                .font(AppFont.nav(12, weight: .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                            Text(f.short)
                                .font(AppFont.nav(11))
                                .foregroundStyle(AppColor.mutedGrey)
                        }
                        Spacer()
                        Text("\(f.points)/\(f.maxPoints)")
                            .font(AppFont.mono(11, weight: .semibold))
                            .foregroundStyle(AppColor.mutedGrey)
                    }
                    .help(f.detail)
                }
            }
        }
    }

    private func checkIcon(_ f: ConfidenceFactor) -> String {
        f.points == f.maxPoints ? "checkmark.circle.fill" : f.points == 0 ? "xmark.circle.fill" : "circle.lefthalf.filled"
    }

    private func checkColor(_ f: ConfidenceFactor) -> Color {
        f.points == f.maxPoints ? AppColor.scoreExcellent : f.points == 0 ? AppColor.scorePoor : AppColor.scoreModerate
    }

    // MARK: - How it works (visual)

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("HOW IT WORKS", icon: "function")
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            cardTitle("Opportunity Score")
                            Text("Plain arithmetic from three factors, not an AI guess.")
                                .font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
                            weightRow("Foot traffic", OpportunityScore.footfallWeight)
                            weightRow("Occupied shopfronts", OpportunityScore.vacancyWeight)
                            weightRow("Business activity", OpportunityScore.densityWeight)
                            TierScale()
                                .padding(.top, 4)
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            cardTitle("Confidence")
                            Text("How well the data backs a score, not how good the spot is.")
                                .font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
                            ForEach(ConfidenceAssessment.rubric, id: \.0) { item in
                                weightRow(item.0, Double(item.1) / 100, suffix: "\(item.1) pts")
                            }
                            HStack(spacing: 12) {
                                levelKey(.high, "75+")
                                levelKey(.medium, "50–74")
                                levelKey(.low, "<50")
                            }
                            .padding(.top, 4)
                        }
                    }
                    card {
                        VStack(alignment: .leading, spacing: 14) {
                            cardTitle("Filters")
                            explainer("clock", "Time of day & day type", "Change which hours of foot traffic count.")
                            explainer("figure.walk", "Footfall level", "Quarters of measured blocks: Low to Very high.")
                            explainer("person.2", "Competition", "Rivals within your search radius.")
                            explainer("parkingsign.circle", "Parking", "Shown for context, not scored.")
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weightRow(_ label: String, _ weight: Double, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(AppFont.nav(12)).foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text(suffix ?? "\(Int((weight * 100).rounded()))%")
                    .font(AppFont.mono(11, weight: .semibold))
                    .foregroundStyle(AppColor.mutedGrey)
            }
            Bar(fraction: weight / 0.4, color: AppColor.gradientTeal)
        }
    }

    private func levelKey(_ level: ConfidenceLevel, _ range: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon).font(.system(size: 10)).foregroundStyle(level.color)
            Text("\(level.rawValue) \(range)")
                .font(AppFont.nav(10))
                .foregroundStyle(AppColor.mutedGrey)
        }
    }

    private func explainer(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.tealAccent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.nav(12, weight: .semibold)).foregroundStyle(AppColor.textPrimary)
                Text(text).font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Data sources

    private var dataSources: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("DATA SOURCES", icon: "tablecells")
                Spacer()
                Button {
                    Task { await store.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(AppFont.nav(12, weight: .semibold))
                        .foregroundStyle(AppColor.tealAccent)
                }
                .buttonStyle(.plain)
                .disabled(store.source == .loading)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(CityDataset.allCases) { dataset in
                    datasetTile(dataset)
                }
            }
            Text("All from City of Melbourne Open Data (CC BY), fetched live. Hover a tile for details, click to open it.")
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.mutedGrey)
        }
    }

    private func datasetTile(_ dataset: CityDataset) -> some View {
        let info = store.datasetInfo(dataset)
        let isLive = dataset == .onStreetParking || dataset == .pedestrianCounts
        return Link(destination: dataset.portalURL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: dataset.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(AppColor.tealAccent)
                    Spacer()
                    if isLive {
                        Text("LIVE")
                            .font(AppFont.mono(9, weight: .bold))
                            .foregroundStyle(AppColor.scoreExcellent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(Capsule().stroke(AppColor.scoreExcellent.opacity(0.6), lineWidth: 1))
                    }
                }
                Text(dataset.shortTitle)
                    .font(AppFont.nav(12, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info?.modified.map { "Updated \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "Updated n/a")
                    .font(AppFont.nav(10))
                    .foregroundStyle(AppColor.mutedGrey)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(12)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(dataset.title)\n\(dataset.usedFor)")
    }

    // MARK: - Trust & privacy

    private var trustAndPrivacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("TRUST & PRIVACY", icon: "lock.shield")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                trustTile("bubble.left.and.exclamationmark.bubble.right", "Chats aren't saved",
                          "Kept in memory only and cleared when you change block, press Clear or quit.")
                trustTile("checkmark.shield", "Grounded in real data",
                          "Loca only uses the numbers on screen and says when something isn't in the data.")
                trustTile("paperplane", "What leaves your Mac",
                          ai.provider == .claude ? "Your question and the block's data go to Anthropic to answer it."
                                                 : "Nothing. The on-device model runs on this Mac.")
                trustTile("info.circle", "Decision support only",
                          "Not financial, legal or planning advice. Check zoning with the City of Melbourne.")
            }
        }
    }

    private func trustTile(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColor.tealAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.nav(13, weight: .semibold)).foregroundStyle(AppColor.textPrimary)
                Text(text).font(AppFont.nav(11)).foregroundStyle(AppColor.mutedGrey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.cardBorder, lineWidth: 1))
    }

    // MARK: - Full methodology (collapsed)

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMethodology.toggle() }
            } label: {
                HStack {
                    sectionTitle("FULL METHODOLOGY & LIMITATIONS", icon: "doc.text.magnifyingglass")
                    Spacer()
                    Image(systemName: showMethodology ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.mutedGrey)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMethodology {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Methodology.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(section.title, systemImage: section.icon)
                                .font(AppFont.nav(13, weight: .semibold))
                                .foregroundStyle(AppColor.tealAccent)
                            ForEach(section.points, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(AppColor.mutedGrey.opacity(0.6)).frame(width: 4, height: 4).padding(.top, 6)
                                    Text(point)
                                        .font(AppFont.nav(12))
                                        .foregroundStyle(AppColor.textPrimary.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(AppColor.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.cardBorder, lineWidth: 1))
            }
        }
    }

    // MARK: - Building blocks

    private func sectionTitle(_ text: String, icon: String, trailing: String? = nil) -> some View {
        HStack {
            Label(text, systemImage: icon)
                .font(AppFont.mono(12, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AppColor.textPrimary.opacity(0.9))
            if let trailing {
                Spacer()
                Text(trailing)
                    .font(AppFont.nav(11))
                    .foregroundStyle(AppColor.mutedGrey)
            }
        }
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.nav(14, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            .background(AppColor.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.cardBorder, lineWidth: 1))
    }
}

// MARK: - Small visual components

/// A thin rounded progress bar on a faint track.
private struct Bar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.textPrimary.opacity(0.07))
                Capsule().fill(color)
                    .frame(width: max(0, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 6)
    }
}

/// 0–100 scale split into the four tiers, with a marker at the score.
private struct ScoreMeter: View {
    let score: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * CGFloat(min(max(score, 0), 100)) / 100
                ZStack(alignment: .leading) {
                    TierStrip(height: 8)
                        .frame(maxHeight: .infinity)
                    Circle()
                        .fill(AppColor.textPrimary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(AppColor.cardSurface, lineWidth: 3))
                        .offset(x: min(max(x - 7, 0), w - 14))
                }
            }
            .frame(height: 14)
            HStack {
                Text("0").font(AppFont.mono(9)).foregroundStyle(AppColor.mutedGrey)
                Spacer()
                Text("Score \(score) of 100")
                    .font(AppFont.mono(10, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Text("100").font(AppFont.mono(9)).foregroundStyle(AppColor.mutedGrey)
            }
        }
    }
}

/// The four tier bands (Poor 0–39, Moderate 40–59, Good 60–79, Excellent 80–100),
/// separated by 2pt gaps.
private struct TierStrip: View {
    var height: CGFloat = 8

    static let bands: [(OpportunityTier, Double)] = [(.poor, 40), (.moderate, 20), (.good, 20), (.excellent, 20)]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let usable = geo.size.width - gap * CGFloat(Self.bands.count - 1)
            HStack(spacing: gap) {
                ForEach(Self.bands, id: \.0) { tier, span in
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(tier.color.opacity(0.8))
                        .frame(width: usable * CGFloat(span / 100), height: height)
                }
            }
        }
        .frame(height: height)
    }
}

/// The tier scale with a legend, for the "How it works" card. The strip is drawn to
/// scale; the legend is evenly spaced so the narrow bands' labels don't collide.
private struct TierScale: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TierStrip(height: 6)
            HStack(alignment: .top, spacing: 6) {
                ForEach(TierStrip.bands, id: \.0) { tier, _ in
                    HStack(alignment: .top, spacing: 5) {
                        Circle().fill(tier.color).frame(width: 7, height: 7).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tier.rawValue)
                                .font(AppFont.nav(10, weight: .semibold))
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(tier.range)
                                .font(AppFont.mono(9))
                                .foregroundStyle(AppColor.mutedGrey)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Status label: coloured icon and text (status always ships with an icon + label, never colour alone).
private struct StatusLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10)).foregroundStyle(color)
            configuration.title
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
