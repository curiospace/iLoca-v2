import SwiftUI

struct LandingView: View {

    /// Which nav item is currently "active" -- drives the mint-green highlight.
    /// Owned by RootScrollContainer so it can stay in sync with actual scroll position.
    @Binding var activeTab: String

    /// Fired when the mascot is tapped -- wired up to open the AI chat panel.
    var onMascotTap: (() -> Void)? = nil

    /// Fired when a nav item is tapped, passing its label -- RootScrollContainer
    /// uses this to scroll to the matching page (where one exists yet).
    var onNavTap: ((String) -> Void)? = nil

    private let navItems = ["How It Works", "About", "Home", "Map", "Guide"]

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
    LandingView(activeTab: .constant("Home"))
        .frame(width: 1400, height: 900)
}
