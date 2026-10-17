import SwiftUI

/// Opportunity Score with an expandable "Why this score?" factor breakdown.
struct ScoreCard: View {
    let score: OpportunityScore
    var startExpanded = false

    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? startExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OPPORTUNITY SCORE")
                        .font(AppFont.mono(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(AppColor.mutedGrey)
                    Text(score.tier.rawValue)
                        .font(AppFont.nav(13, weight: .semibold))
                        .foregroundStyle(score.tier.color)
                }
                Spacer()
                Text("\(score.value)")
                    .font(AppFont.headline(30))
                    .foregroundStyle(score.tier.color)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded = !isExpanded }
            } label: {
                HStack(spacing: 4) {
                    Text("Why this score?")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(AppFont.nav(11, weight: .semibold))
                .foregroundStyle(AppColor.tealAccent)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScoreBreakdownView(score: score)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(score.tier.color.opacity(0.4), lineWidth: 1))
    }
}

struct ScoreBreakdownView: View {
    let score: OpportunityScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(score.components) { c in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(c.kind.rawValue)
                            .font(AppFont.nav(12, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary.opacity(c.isMissing ? 0.5 : 0.9))
                        Spacer()
                        if let v = c.value {
                            Text("\(Int(v.rounded())) × \(Int((c.appliedWeight * 100).rounded()))% = \(Int(c.contribution.rounded()))")
                                .font(AppFont.mono(10))
                                .foregroundStyle(AppColor.mutedGrey)
                        } else {
                            Text("no data · excluded")
                                .font(AppFont.mono(10))
                                .foregroundStyle(AppColor.scoreModerate)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColor.textPrimary.opacity(0.06))
                            Capsule().fill(AppColor.tealAccent.opacity(c.isMissing ? 0 : 0.85))
                                .frame(width: geo.size.width * CGFloat((c.value ?? 0) / 100))
                        }
                    }
                    .frame(height: 5)
                    Text(c.detail)
                        .font(AppFont.nav(10))
                        .foregroundStyle(AppColor.mutedGrey)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Confidence level card shown directly under the Opportunity Score.
struct ConfidenceCard: View {
    let confidence: ConfidenceAssessment
    var startExpanded = false

    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? startExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIDENCE LEVEL")
                        .font(AppFont.mono(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(AppColor.mutedGrey)
                    Label(confidence.level.rawValue, systemImage: confidence.level.icon)
                        .font(AppFont.nav(14, weight: .semibold))
                        .foregroundStyle(confidence.level.color)
                }
                Spacer()
                ZStack {
                    Circle().stroke(AppColor.textPrimary.opacity(0.08), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(confidence.points) / 100)
                        .stroke(confidence.level.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(confidence.points)")
                        .font(AppFont.nav(12, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .frame(width: 40, height: 40)
            }

            Text(confidence.summary)
                .font(AppFont.nav(11))
                .foregroundStyle(AppColor.textPrimary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded = !isExpanded }
            } label: {
                HStack(spacing: 4) {
                    Text("What affects confidence?")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .font(AppFont.nav(11, weight: .semibold))
                .foregroundStyle(AppColor.tealAccent)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(confidence.factors) { f in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(f.points)/\(f.maxPoints)")
                                .font(AppFont.mono(10, weight: .semibold))
                                .foregroundStyle(f.points == f.maxPoints ? AppColor.scoreExcellent : f.points == 0 ? AppColor.scorePoor : AppColor.scoreModerate)
                                .frame(width: 38, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(AppFont.nav(11, weight: .semibold)).foregroundStyle(AppColor.textPrimary.opacity(0.9))
                                Text(f.detail).font(AppFont.nav(10)).foregroundStyle(AppColor.mutedGrey)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(AppColor.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(confidence.level.color.opacity(0.35), lineWidth: 1))
    }
}

/// One-line data freshness indicator ("Businesses: 2024 census · Foot traffic: to 15 Oct · Live").
struct FreshnessLine: View {
    let store: CityDataStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(store.freshnessLine)
                .font(AppFont.nav(10))
                .foregroundStyle(AppColor.mutedGrey)
                .lineLimit(2)
        }
    }

    private var icon: String {
        switch store.source {
        case .live: return "dot.radiowaves.left.and.right"
        case .cached: return "externaldrive"
        case .loading: return "arrow.triangle.2.circlepath"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch store.source {
        case .live: return AppColor.scoreExcellent
        case .cached: return AppColor.scoreModerate
        default: return AppColor.scorePoor
        }
    }
}
