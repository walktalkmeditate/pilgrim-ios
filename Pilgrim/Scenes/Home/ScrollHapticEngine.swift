import SwiftUI

enum HapticEvent: Equatable {
    case none
    case lightDot(Int)
    case heavyDot(Int)
    case milestone(Int)
}

@Observable
class ScrollHapticState {

    var dotPositions: [CGFloat] = []
    var dotSizes: [CGFloat] = []
    var milestonePositions: [CGFloat] = []

    private(set) var currentEvent: HapticEvent = .none
    private var lastTriggeredIndex: Int?
    private var lastTriggeredMilestone: Int?

    func handleScrollOffset(_ offset: CGFloat, viewportHeight: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let viewCenter = -offset + viewportHeight / 2

        if let dotEvent = checkDotCrossing(viewCenter: viewCenter) {
            currentEvent = dotEvent
            return
        }

        if let milestoneEvent = checkMilestoneCrossing(viewCenter: viewCenter) {
            currentEvent = milestoneEvent
        }
    }

    private func checkDotCrossing(viewCenter: CGFloat) -> HapticEvent? {
        let threshold: CGFloat = 20

        for (index, dotY) in dotPositions.enumerated() {
            guard abs(viewCenter - dotY) < threshold else { continue }
            guard lastTriggeredIndex != index else { continue }

            lastTriggeredIndex = index
            let isLarge = index < dotSizes.count && dotSizes[index] > 15
            return isLarge ? .heavyDot(index) : .lightDot(index)
        }
        return nil
    }

    private func checkMilestoneCrossing(viewCenter: CGFloat) -> HapticEvent? {
        let threshold: CGFloat = 25

        for (index, milestoneY) in milestonePositions.enumerated() {
            guard abs(viewCenter - milestoneY) < threshold else { continue }
            guard lastTriggeredMilestone != index else { continue }

            lastTriggeredMilestone = index
            return .milestone(index)
        }
        return nil
    }
}
