import SwiftUI

/// The iLoca mascot, fully animated natively:
/// - a gentle continuous idle float (bob up/down)
/// - a periodic arm wave (the ball-armed left arm swings a few times, then rests, then repeats)
/// - twinkling eye sparkles that pulse softly and independently
///
/// Requires three image assets in Assets.xcassets:
///   "MascotBody"  -- the full mascot with the left ball+arm removed (static)
///   "MascotArm"   -- just the left ball+stub, positioned to align exactly over MascotBody
///   (both images share the same canvas size/aspect ratio so they overlay perfectly)
struct AnimatedMascotView: View {

    /// Called when the mascot is tapped -- this is the hook the AI chat panel
    /// will attach to later (mascot becomes the AI entry point).
    var onTap: (() -> Void)? = nil

    // Pivot for the arm's rotation, expressed as a fraction of the image's own
    // bounds (measured from the source artwork). This is where the arm "attaches"
    // to the body, so it swings from the shoulder rather than from its own center.
    private let armPivot = UnitPoint(x: 0.238, y: 0.580)

    // Eye positions, expressed as fractions of the mascot's displayed frame,
    // used to place the twinkle sparkles precisely over each eye.
    private let leftEye = UnitPoint(x: 0.458, y: 0.395)
    private let rightEye = UnitPoint(x: 0.771, y: 0.386)

    private let startDate = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let bob = idleBob(elapsed: elapsed)
            let armAngle = waveAngle(elapsed: elapsed)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    Image("MascotBody")
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)

                    Image("MascotArm")
                        .resizable()
                        .scaledToFit()
                        .frame(width: w, height: h)
                        .rotationEffect(.degrees(armAngle), anchor: armPivot)

                    twinkle(elapsed: elapsed, phase: 0)
                        .position(x: leftEye.x * w, y: leftEye.y * h)

                    twinkle(elapsed: elapsed, phase: 1.4)
                        .position(x: rightEye.x * w, y: rightEye.y * h)
                }
                .frame(width: w, height: h)
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }
            }
            .offset(y: bob)
        }
    }

    // MARK: - Motion curves

    /// Slow, continuous up/down float -- always running, very subtle.
    private func idleBob(elapsed: TimeInterval) -> CGFloat {
        let period = 3.2
        let amplitude: CGFloat = 8
        return CGFloat(sin(elapsed / period * 2 * .pi)) * amplitude
    }

    /// Produces a burst of a few gentle wags, then a rest, on a loop:
    /// wave for ~2.2s, rest for ~2.0s, repeat every ~4.2s.
    private func waveAngle(elapsed: TimeInterval) -> Double {
        let cycle = 4.2
        let waveDuration = 2.2
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        guard t < waveDuration else { return 0 }

        let maxAngle = 9.0 // degrees
        let wags = 3.0
        let envelope = sin(t / waveDuration * .pi)
        let wag = sin(t / waveDuration * .pi * wags)
        return wag * envelope * maxAngle
    }

    /// A soft sparkle that pulses in and out, offset in time by `phase` so the
    /// two eyes don't blink in perfect unison.
    @ViewBuilder
    private func twinkle(elapsed: TimeInterval, phase: Double) -> some View {
        let period = 3.6
        let t = (elapsed + phase).truncatingRemainder(dividingBy: period)
        let visibleWindow = 0.9
        let progress = t / visibleWindow
        let envelope = t < visibleWindow ? sin(progress * .pi) : 0

        Image(systemName: "sparkle")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .opacity(envelope * 1.4)
            .scaleEffect(0.6 + envelope * 0.6)
    }
}

#Preview {
    ZStack {
        AppColor.navyBackground.ignoresSafeArea()
        AnimatedMascotView()
            .frame(width: 260, height: 316)
    }
}
