import SwiftUI

struct GuidesView: View {
    @Binding var activeTab: String
    var onNavTap: ((String) -> Void)? = nil

    @State private var guidesAI = GuidesAdvisorAI()
    @State private var selectedBucket: GuideBucket? = nil
    @State private var showPDF = false

    var body: some View {
        ZStack {
            ParticleBackgroundView()

            VStack(spacing: 0) {
                navBar
                    .padding(.top, 24)

                HStack(alignment: .top, spacing: 24) {
                    leftContent
                        .frame(maxWidth: .infinity)

                    GuidesAIPanelView(ai: guidesAI)
                        .frame(width: 380)
                        .padding(.trailing, 28)
                }
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showPDF) {
            if let selectedBucket {
                GuidePDFViewerSheet(bucket: selectedBucket)
            }
        }
        .task {
            guidesAI.checkAvailability()
            await guidesAI.prepare()
        }
    }

    // MARK: - Left column: heading + wave + detail card

    private var leftContent: some View {
        VStack(spacing: 32) {
            VStack(spacing: 4) {
                Text("YOUR SME JOURNEY")
                    .font(AppFont.mono(12, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(AppColor.mintLight)
                Text("GUIDES FOR MELBOURNE\nCBD BUSINESSES")
                    .font(AppFont.headline(40))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.headlineGradient)
            }
            .padding(.top, 12)

            GuideWaveView(selected: $selectedBucket)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 60)

            if let selectedBucket {
                GuideDetailCard(bucket: selectedBucket) {
                    showPDF = true
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Nav bar
    // Matches LandingView's navBar exactly: logo dot + wordmark, active-tab
    // highlighted in mint, everything else muted grey.

    private let navItems = ["How It Works", "About", "Home", "Map", "Guide"]

    private var navBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColor.tealAccent)
                    .frame(width: 9, height: 9)
                Text("iLoca")
                    .font(AppFont.nav(19, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 26) {
                ForEach(navItems, id: \.self) { item in
                    Text(item)
                        .font(AppFont.nav(14, weight: item == activeTab ? .semibold : .regular))
                        .foregroundStyle(item == activeTab ? AppColor.mintLight : AppColor.mutedGrey)
                        .contentShape(Rectangle())
                        .onTapGesture { onNavTap?(item) }
                }
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 40)
    }
}

