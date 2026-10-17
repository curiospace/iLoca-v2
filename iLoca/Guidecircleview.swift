import SwiftUI

struct GuideCircleView: View {
    let bucket: GuideBucket
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(bucket.accent.opacity(isSelected ? 0.35 : 0.16))
                    .frame(width: isSelected ? 118 : 102, height: isSelected ? 118 : 102)
                    .overlay(
                        Circle().stroke(bucket.accent, lineWidth: isSelected ? 2.5 : 1.5)
                    )
                    .shadow(color: bucket.accent.opacity(isSelected ? 0.45 : 0), radius: 16)

                Image(systemName: bucket.icon)
                    .font(.system(size: isSelected ? 36 : 30, weight: .medium))
                    .foregroundStyle(bucket.accent)
            }

            Text(bucket.title.uppercased())
                .font(AppFont.mono(12, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.mutedGrey)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isSelected)
        .contentShape(Rectangle())
    }
}
