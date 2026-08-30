//
//  EffortlessPaging.swift
//  iLoca
//
//  Created by Afrah Khan on 30/8/2026.
//


import SwiftUI

/// A page-snapping scroll behavior that's much more sensitive than the built-in
/// `.paging` style. A small scroll nudge (or any real flick velocity) is enough
/// to commit to the next/previous page -- no big drag required.
struct EffortlessPaging: ScrollTargetBehavior {

    /// How far into a page (as a fraction, 0...1) you need to scroll before it
    /// commits to moving on, absent any real velocity. Lower = more effortless.
    var threshold: CGFloat = 0.08

    /// Velocity (points/sec) above which a flick commits to the next page
    /// regardless of how far it's scrolled.
    var velocityThreshold: CGFloat = 40

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let pageHeight = context.containerSize.height
        guard pageHeight > 0 else { return }

        let startPage = (context.originalTarget.rect.minY / pageHeight).rounded()
        let progressIntoGesture = (target.rect.minY - startPage * pageHeight) / pageHeight
        let velocity = context.velocity.dy

        var pageDelta: CGFloat = 0
        if abs(velocity) > velocityThreshold {
            pageDelta = velocity > 0 ? 1 : -1
        } else if abs(progressIntoGesture) > threshold {
            pageDelta = progressIntoGesture > 0 ? 1 : -1
        }

        let targetPage = startPage + pageDelta
        target.rect.origin.y = targetPage * pageHeight
    }
}