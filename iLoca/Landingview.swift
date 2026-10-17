import SwiftUI

struct LandingView: View {

    /// Fired when the mascot is tapped -- wired up to open the AI chat panel.
    var onMascotTap: (() -> Void)? = nil

    /// Fired when a nav item is tapped -- RootScrollContainer scrolls to that page.
    var onNavTap: ((AppPage) -> Void)? = nil

    var body: some View {
        ZStack {
            ParticleBackgroundView()

            VStack(spacing: 20) {
                navBar
                Spacer(minLength: 20)
                headline
                subheadline
                Spacer(minLength: 24)
                AnimatedMascotView(onTap: onMascotTap)
                    .frame(width: 150, height: 182)
                scrollHint
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        TopNavBar(activePage: .home, onNavTap: onNavTap)
            .padding(.top, 22)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 0) {
            Text("FIND THE")
            Text("RIGHT PLACE")
        }
        .font(AppFont.headline(100))
        .tracking(-1.0)
        .multilineTextAlignment(.center)
        .foregroundStyle(AppColor.headlineGradient)
    }

    private var subheadline: some View {
        Text("BUILD WITH CONFIDENCE")
            .font(AppFont.subheadline(40))
            .tracking(0.5)
            .foregroundStyle(AppColor.mintLight)
            .padding(.top, 14)
    }

    // MARK: - Scroll hint

    private var scrollHint: some View {
        VStack(spacing: 6) {
            Text("SCROLL TO DISCOVER")
                .font(AppFont.mono(11, weight: .medium))
                .tracking(3.0)
                .foregroundStyle(AppColor.mutedGrey)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.mutedGrey)
        }
    }
}

#Preview {
    LandingView()
        .frame(width: 1400, height: 900)
}
