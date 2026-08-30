import SwiftUI

/// A single ambient particle drifting slowly across the background.
private struct Particle: Identifiable {
    let id = UUID()
    var startX: CGFloat        // 0...1 relative start position
    var y: CGFloat             // 0...1 relative vertical position (fixed, no vertical drift)
    var size: CGFloat
    var speed: CGFloat         // relative units per second (very small -> very slow)
    var color: Color
    var opacity: Double
}

/// The full landing-page background: dark navy base, a faint grid that drifts
/// horizontally very slowly, and a handful of soft ambient particles drifting
/// in parallax (different depths = different speed/size/opacity) also very slowly.
struct ParticleBackgroundView: View {

    private let particles: [Particle] = ParticleBackgroundView.makeParticles()
    private let gridSpacing: CGFloat = 44
    private let gridSpeed: CGFloat = 2.4      // points per second, very slow
    private let startDate = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)

                // Base background
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(AppColor.navyBackground))

                // Slowly drifting grid
                drawGrid(in: &context, size: size, elapsed: elapsed)

                // Ambient particles, each with its own very slow horizontal drift
                for particle in particles {
                    drawParticle(particle, in: &context, size: size, elapsed: elapsed)
                }
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let offset = (CGFloat(elapsed) * gridSpeed).truncatingRemainder(dividingBy: gridSpacing)
        var path = Path()

        var x = -gridSpacing + offset
        while x < size.width + gridSpacing {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += gridSpacing
        }
        var y: CGFloat = 0
        while y < size.height + gridSpacing {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += gridSpacing
        }
        context.stroke(path, with: .color(AppColor.gridLine), lineWidth: 1)
    }

    private func drawParticle(_ particle: Particle, in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        // Very slow horizontal drift that loops seamlessly by wrapping 0...1.2
        // (the extra 0.2 keeps particles fully off-screen before they wrap back)
        let travel = CGFloat(elapsed) * particle.speed
        let normalizedX = (particle.startX + travel).truncatingRemainder(dividingBy: 1.2)
        let x = normalizedX * size.width
        let yPos = particle.y * size.height

        let rect = CGRect(x: x - particle.size / 2, y: yPos - particle.size / 2,
                           width: particle.size, height: particle.size)
        context.opacity = particle.opacity
        context.fill(Path(ellipseIn: rect), with: .color(particle.color))
        context.opacity = 1
    }

    private static func makeParticles() -> [Particle] {
        let palette: [Color] = [AppColor.tealAccent, AppColor.gradientAmber, AppColor.gradientRoyalBlue, AppColor.mutedGrey]
        var generator = SystemRandomNumberGenerator()
        var result: [Particle] = []
        for i in 0..<150 {
            let color = palette[i % palette.count]
            result.append(
                Particle(
                    startX: CGFloat.random(in: 0...1.2, using: &generator),
                    y: CGFloat.random(in: 0.03...0.97, using: &generator),
                    size: CGFloat.random(in: 2...5, using: &generator),
                    speed: CGFloat.random(in: 0.004...0.012, using: &generator), // very slow
                    color: color,
                    opacity: Double.random(in: 0.25...0.7, using: &generator)
                )
            )
        }
        return result
    }
}

#Preview {
    ParticleBackgroundView()
        .frame(width: 900, height: 600)
}
