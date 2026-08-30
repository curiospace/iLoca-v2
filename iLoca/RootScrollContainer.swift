import SwiftUI

struct RootScrollContainer: View {

    @State private var activeTab: String = "Home"

    // Shared AI session so the conversation persists as the user scrolls
    // between the landing page and the map, plus the bottom-right entry point.
    @State private var ai = LocationAdvisorAI()
    @State private var showAIPanel: Bool = false
    @State private var currentBlockLabel: String? = nil

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        LandingView(
                            activeTab: $activeTab,
                            onMascotTap: { showAIPanel = true },
                            onNavTap: { item in handleNavTap(item, proxy: proxy) }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id("home")

                        ContentView(
                            activeTab: $activeTab,
                            onNavTap: { item in handleNavTap(item, proxy: proxy) },
                            currentBlockLabel: $currentBlockLabel,
                            ai: ai
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id("map")

                        GuidesView(
                            activeTab: $activeTab,
                            onNavTap: { item in handleNavTap(item, proxy: proxy) }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id("guide")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomTrailing) {
            aiOverlay
        }
        .onAppear {
            ai.checkAvailability()
            // Immediate fallback so the AI button works even before the user
            // scrolls down to the map page — LazyVStack means ContentView's
            // own onAppear (which grounds this in real block data) may not
            // fire until the map page is actually scrolled into view.
            ai.startGeneralSession(overview: "No block data has loaded yet — ask again once you've scrolled to the Map page for real Melbourne data.")
        }
    }

    // MARK: - Persistent AI entry point (Home + Map only — Guides has its own
    // always-visible panel via GuidesAIPanelView, grounded in the guide PDFs
    // instead of block data)

    @ViewBuilder
    private var aiOverlay: some View {
        // Hide the floating location-advisor button/panel while on the Guides
        // page so it doesn't compete with GuidesView's own right-side panel.
        if activeTab != "Guide" {
            VStack(alignment: .trailing, spacing: 16) {
                if showAIPanel {
                    AIPanelView(
                        ai: ai,
                        blockLabel: currentBlockLabel ?? "General Melbourne overview",
                        isVisible: $showAIPanel
                    )
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

    private func handleNavTap(_ item: String, proxy: ScrollViewProxy) {
        activeTab = item
        let targetId: String?
        switch item {
        case "Home": targetId = "home"
        case "Map": targetId = "map"
        case "Guide": targetId = "guide"
        default: targetId = nil // "How It Works", "About" — no page yet
        }
        if let targetId {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(targetId, anchor: .top)
            }
        }
    }
}
