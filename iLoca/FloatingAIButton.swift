import SwiftUI

/// The persistent AI entry point, bottom-right, on every page.
/// Fully static per product decision — no rotation, no idle bob/wave, no
/// twinkle. Uses the real Apple Intelligence ring artwork (add
/// "AppleIntelligenceRing" to Assets.xcassets) with the mascot's body+arm
/// drawn once in their resting pose on top — same artwork as the animated
/// landing-page mascot, just rendered as a still image here.
struct FloatingAIButton: View {
    var onTap: () -> Void

    private let buttonSize: CGFloat = 88
    private let mascotSize: CGFloat = 42

    var body: some View {
        ZStack {
            Image("AppleIntelligenceRing")
                .resizable()
                .scaledToFit()
                .frame(width: buttonSize, height: buttonSize)
                .shadow(color: AppColor.gradientRoyalBlue.opacity(0.3), radius: 8)

//            Circle()
//                .fill(AppColor.navyBackground)
//                .frame(width: mascotSize + 8, height: mascotSize + 8)

            // Static resting pose: body + arm with no rotation, no bob.
            ZStack {
                Image("MascotBody")
                    .resizable()
                    .scaledToFit()
                Image("MascotArm")
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: mascotSize, height: mascotSize)
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
    }
}
