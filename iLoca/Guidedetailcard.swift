//
//  GuideDetailCard.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

struct GuideDetailCard: View {
    let bucket: GuideBucket
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: bucket.icon)
                    .foregroundStyle(bucket.accent)
                Text(bucket.documentTitle)
                    .font(AppFont.nav(15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }

            Text(bucket.subtitle)
                .font(AppFont.nav(12))
                .foregroundStyle(AppColor.mutedGrey)

            Button(action: onOpen) {
                Label("Open Guide", systemImage: "doc.text.fill")
                    .font(AppFont.nav(12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(bucket.accent.opacity(0.2))
                    .foregroundStyle(bucket.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(bucket.accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}