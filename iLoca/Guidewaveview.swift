import SwiftUI

/// Lays the four guide buckets out as a gentle up/down wave across the width
/// of the page, connected by a dashed curve, echoing the "SME journey" framing.
struct GuideWaveView: View {
    @Binding var selected: GuideBucket?

    private let buckets = GuideBucket.allCases
    private let amplitude: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let midY = geo.size.height / 2
            let spacing = width / CGFloat(buckets.count + 1)

            ZStack {
                wavePath(midY: midY, spacing: spacing)
                    .stroke(
                        LinearGradient(
                            colors: [AppColor.gradientTeal, AppColor.gradientRoyalBlue,
                                     AppColor.gradientAmber, AppColor.tealAccent],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, dash: [2, 7])
                    )
                    .opacity(0.55)

                ForEach(Array(buckets.enumerated()), id: \.element) { index, bucket in
                    let x = spacing * CGFloat(index + 1)
                    let y = midY + waveOffset(index: index)

                    GuideCircleView(bucket: bucket, isSelected: selected == bucket)
                        .position(x: x, y: y)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                selected = (selected == bucket) ? nil : bucket
                            }
                        }
                }
            }
        }
        .frame(height: 300)
    }

    private func waveOffset(index: Int) -> CGFloat {
        index.isMultiple(of: 2) ? -amplitude : amplitude
    }

    private func wavePath(midY: CGFloat, spacing: CGFloat) -> Path {
        var path = Path()
        let points: [CGPoint] = (0..<buckets.count).map { i in
            CGPoint(x: spacing * CGFloat(i + 1), y: midY + waveOffset(index: i))
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let midX = (prev.x + curr.x) / 2
            path.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }
        return path
    }
}
