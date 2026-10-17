import SwiftUI

struct RootScrollContainer: View {

    @State private var activePage: AppPage = .home
    @State private var scrolledPage: AppPage? = .home

    // Shared, app-wide state: city data + selection + filters, and the map advisor's
    // ephemeral chat (kept while scrolling between Home and Map).
    @State private var store = CityDataStore()
    @State private var ai = LocationAdvisorAI()
    @State private var showAIPanel = false
    /// Programmatic scroll requests (launch, debug arguments), applied through the proxy.
    @State private var pendingScroll: AppPage?

    private struct IssueSheetItem: Identifiable {
        let id = UUID()
        let context: IssueContext
    }
    @State private var issueSheet: IssueSheetItem?

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        LandingView(
                            onMascotTap: { showAIPanel = true },
                            onNavTap: { go(to: $0, proxy: proxy) }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(AppPage.home)

                        ContentView(onNavTap: { go(to: $0, proxy: proxy) }, store: store, ai: ai)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(AppPage.map)

                        GuidesView(onNavTap: { go(to: $0, proxy: proxy) })
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(AppPage.guide)

                        InfoView(onNavTap: { go(to: $0, proxy: proxy) }, store: store)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(AppPage.info)
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrolledPage)
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                // Always open on Home, even if the window restored an old scroll offset.
                .onAppear { proxy.scrollTo(AppPage.home, anchor: .top) }
                .onChange(of: pendingScroll) { _, page in
                    guard let page else { return }
                    proxy.scrollTo(page, anchor: .top)
                    activePage = page
                    pendingScroll = nil
                }
            }
        }
        // Pages are laid out below the window's title bar so the nav isn't clipped
        // in a normal (non-full-screen) window.
        .background(AppColor.navyBackground)
        .overlay(alignment: .bottomTrailing) { aiOverlay }
        .environment(\.reportIssue) { context in
            var context = context
            // Fill in block context for reports raised from chat answers.
            if context.blockId == nil, let block = store.selectedBlock {
                context.blockId = block.blockId
                context.blockArea = block.area
                context.score = store.score(for: block)?.value
            }
            if context.dataFreshness == nil { context.dataFreshness = store.freshnessLine }
            issueSheet = IssueSheetItem(context: context)
        }
        .sheet(item: $issueSheet) { item in
            ReportIssueSheet(context: item.context)
        }
        .onChange(of: scrolledPage) { _, page in
            if let page { activePage = page }
        }
        .task {
            ai.reground(store: store)
            await store.load()
            ai.reground(store: store)
            #if DEBUG
            applyDebugLaunchArguments()
            #endif
        }
    }

    // MARK: - Floating Loca entry point (Home + Map only; Guide and Info have
    // their own always-visible assistant panels)

    @ViewBuilder
    private var aiOverlay: some View {
        if activePage == .home || activePage == .map {
            VStack(alignment: .trailing, spacing: 16) {
                if showAIPanel {
                    AIPanelView(ai: ai, store: store, isVisible: $showAIPanel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                FloatingAIButton {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showAIPanel.toggle()
                    }
                }
            }
            .padding(24)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showAIPanel)
        }
    }

    #if DEBUG
    /// Development helper: `-iLocaPage Map -iLocaBlock 25 -iLocaCategory FnB -iLocaTab RIVALS`
    /// opens straight into a state, for screenshots and manual QA.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "iLocaCategory") { store.filters.businessCategory = BusinessCategory(rawValue: raw) }
        if defaults.bool(forKey: "iLocaFootfallZones") { store.filters.showFootfallZones = true }
        if defaults.bool(forKey: "iLocaParking") {
            store.filters.showCarParks = true
            store.filters.showOnStreetParking = true
            store.filters.showBusinessDots = false
        }
        if let raw = defaults.string(forKey: "iLocaTime") { store.filters.timesOfDay = [TimeOfDay(rawValue: raw)].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) } }
        if defaults.object(forKey: "iLocaBlock") != nil { store.selectedBlockId = defaults.integer(forKey: "iLocaBlock") }
        if let raw = defaults.string(forKey: "iLocaPage"), let page = AppPage(rawValue: raw) {
            pendingScroll = page
        }
        if defaults.bool(forKey: "iLocaShowChat") { showAIPanel = true }
        if let question = defaults.string(forKey: "iLocaAsk") {
            showAIPanel = true
            // Wait for the block-selection change to re-ground (and clear) the chat first.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await store.loadPremises(for: store.selectedBlockId ?? -1)
                ai.ask(question, store: store)
            }
        }
    }
    #endif

    private func go(to page: AppPage, proxy: ScrollViewProxy) {
        activePage = page
        withAnimation(.easeInOut(duration: 0.5)) {
            proxy.scrollTo(page, anchor: .top)
        }
    }
}
