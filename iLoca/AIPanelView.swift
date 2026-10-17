import SwiftUI

/// Floating Loca panel on Home and Map, grounded in the selected block (or the
/// whole city when nothing is selected).
struct AIPanelView: View {
    let ai: LocationAdvisorAI
    let store: CityDataStore
    @Binding var isVisible: Bool

    private var blockLabel: String {
        store.selectedBlock.map { "Block \($0.blockId) · \($0.area)" } ?? "City-wide overview"
    }

    private var suggestions: [String] {
        if store.selectedBlock != nil {
            let type = store.filters.businessCategory?.rawValue.lowercased() ?? "café"
            return [
                "Why does this block have this score?",
                "How busy is it at lunchtime?",
                "Is this a good spot for a \(type == "fnb" ? "café" : type + " business")?",
                "Who are the main competitors here?",
                "How confident should I be in this data?"
            ]
        }
        return [
            "Which areas have the lowest vacancy?",
            "Where is foot traffic highest?",
            "Which blocks score best for a café?",
            "How does iLoca score a location?"
        ]
    }

    var body: some View {
        LocaChatPanel(
            title: "Loca · Location Advisor",
            subtitle: blockLabel,
            session: ai.session,
            emptyTitle: store.selectedBlock == nil
                ? "Ask about Melbourne's blocks, or select one on the map for detail."
                : "Ask about this location",
            suggestions: suggestions,
            placeholder: "Ask about this location…",
            onClose: { isVisible = false },
            onAsk: { ai.ask($0, store: store) }
        )
        .frame(width: 400, height: 540)
    }
}
