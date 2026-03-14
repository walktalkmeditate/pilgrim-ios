import UIKit
import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

class ScrollHapticEngine {

    private var lastTriggeredIndex: Int?
    private var lastTriggeredMilestone: Int?

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)

    var dotPositions: [CGFloat] = []
    var dotSizes: [CGFloat] = []
    var milestonePositions: [CGFloat] = []

    func prepare() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
    }

    func handleScrollOffset(_ offset: CGFloat, viewportHeight: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let viewCenter = -offset + viewportHeight / 2

        checkDotCrossing(viewCenter: viewCenter)
        checkMilestoneCrossing(viewCenter: viewCenter)
    }

    private func checkDotCrossing(viewCenter: CGFloat) {
        let threshold: CGFloat = 20

        for (index, dotY) in dotPositions.enumerated() {
            guard abs(viewCenter - dotY) < threshold else { continue }
            guard lastTriggeredIndex != index else { continue }

            lastTriggeredIndex = index
            let isLargeDot = index < dotSizes.count && dotSizes[index] > 15
            if isLargeDot {
                mediumGenerator.impactOccurred()
            } else {
                lightGenerator.impactOccurred()
            }
            return
        }
    }

    private func checkMilestoneCrossing(viewCenter: CGFloat) {
        let threshold: CGFloat = 25

        for (index, milestoneY) in milestonePositions.enumerated() {
            guard abs(viewCenter - milestoneY) < threshold else { continue }
            guard lastTriggeredMilestone != index else { continue }

            lastTriggeredMilestone = index
            rigidGenerator.impactOccurred()
            return
        }
    }
}
