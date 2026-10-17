import SwiftUI

struct GuidesView: View {
    var onNavTap: ((AppPage) -> Void)? = nil

    @State private var guidesAI = GuidesAdvisorAI()
    @State private var selectedBucket: GuideBucket? = nil
    @State private var showPDF = false

    var body: some View {
        ZStack {
            ParticleBackgroundView()

            VStack(spacing: 0) {
                TopNavBar(activePage: .guide, onNavTap: onNavTap)
                    .padding(.top, 22)
                    .padding(.horizontal, 40)

                HStack(alignment: .top, spacing: 24) {
                    leftContent
                        .frame(maxWidth: .infinity)

                    GuidesAIPanelView(ai: guidesAI)
                        .frame(width: 380)
                        .padding(.trailing, 28)
                        .padding(.bottom, 28)
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
}
