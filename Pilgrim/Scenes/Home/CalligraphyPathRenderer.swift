import SwiftUI

struct CalligraphyPathRenderer {

    struct DotPosition {
        let center: CGPoint
        let yOffset: CGFloat
    }

    let snapshots: [WalkSnapshot]
    let width: CGFloat

    private let baseStrokeWidth: CGFloat = 1.5
    private let maxStrokeWidth: CGFloat = 4.5
    private let verticalSpacing: CGFloat = 90
    private let maxMeander: CGFloat = 100
    private let topInset: CGFloat = 40

    var totalHeight: CGFloat {
        guard !snapshots.isEmpty else { return 200 }
        return topInset + CGFloat(snapshots.count) * verticalSpacing + verticalSpacing
    }

    func dotPositions() -> [DotPosition] {
        guard !snapshots.isEmpty else {
            let center = CGPoint(x: width / 2, y: topInset + verticalSpacing / 2)
            return [DotPosition(center: center, yOffset: topInset + verticalSpacing / 2)]
        }

        return snapshots.enumerated().map { index, snapshot in
            let y = topInset + CGFloat(index) * verticalSpacing + verticalSpacing / 2
            let x = xPosition(for: snapshot, at: index)
            return DotPosition(center: CGPoint(x: x, y: y), yOffset: y)
        }
    }

    func segmentPaths() -> [(path: Path, index: Int)] {
        let positions = dotPositions()
        guard positions.count >= 2 else { return [] }

        var segments: [(path: Path, index: Int)] = []

        for i in 0..<(positions.count - 1) {
            let start = positions[i].center
            let end = positions[i + 1].center

            let strokeWidth = segmentWidth(for: i)
            let halfWidth = strokeWidth / 2

            let midY = (start.y + end.y) / 2
            let cpOffset = seed(for: i) * maxMeander * 0.4

            let cp1 = CGPoint(x: start.x + cpOffset, y: midY - verticalSpacing * 0.2)
            let cp2 = CGPoint(x: end.x - cpOffset, y: midY + verticalSpacing * 0.2)

            var segPath = Path()

            let leftStart = CGPoint(x: start.x - halfWidth, y: start.y)
            let leftCP1 = CGPoint(x: cp1.x - halfWidth, y: cp1.y)
            let leftCP2 = CGPoint(x: cp2.x - halfWidth, y: cp2.y)
            let leftEnd = CGPoint(x: end.x - halfWidth, y: end.y)

            let rightStart = CGPoint(x: start.x + halfWidth, y: start.y)
            let rightCP1 = CGPoint(x: cp1.x + halfWidth, y: cp1.y)
            let rightCP2 = CGPoint(x: cp2.x + halfWidth, y: cp2.y)
            let rightEnd = CGPoint(x: end.x + halfWidth, y: end.y)

            segPath.move(to: leftStart)
            segPath.addCurve(to: leftEnd, control1: leftCP1, control2: leftCP2)
            segPath.addLine(to: rightEnd)
            segPath.addCurve(to: rightStart, control1: rightCP2, control2: rightCP1)
            segPath.closeSubpath()

            segments.append((path: segPath, index: i))
        }

        return segments
    }

    func emptyStatePath() -> Path {
        let positions = dotPositions()
        var path = Path()
        let center = positions.first?.center ?? CGPoint(x: width / 2, y: topInset + 40)
        let trailLength: CGFloat = 120
        let halfWidth: CGFloat = 1.0

        path.move(to: CGPoint(x: center.x - halfWidth, y: center.y))
        path.addLine(to: CGPoint(x: center.x - halfWidth * 0.2, y: center.y + trailLength))
        path.addLine(to: CGPoint(x: center.x + halfWidth * 0.2, y: center.y + trailLength))
        path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
        path.closeSubpath()

        return path
    }

    private func xPosition(for snapshot: WalkSnapshot, at index: Int) -> CGFloat {
        let centerX = width / 2
        let hashValue = deterministicHash(snapshot)
        let normalizedOffset = CGFloat(hashValue % 1000) / 1000.0 - 0.5
        return centerX + normalizedOffset * maxMeander * 1.6
    }

    func segmentWidth(for index: Int) -> CGFloat {
        guard index < snapshots.count else { return baseStrokeWidth }
        let snapshot = snapshots[index]
        guard snapshot.averagePace > 0 else { return baseStrokeWidth }

        let minPace: Double = 300
        let maxPace: Double = 900
        let clampedPace = min(max(snapshot.averagePace, minPace), maxPace)
        let normalized = (clampedPace - minPace) / (maxPace - minPace)

        return baseStrokeWidth + CGFloat(normalized) * (maxStrokeWidth - baseStrokeWidth)
    }

    private func seed(for index: Int) -> CGFloat {
        guard index < snapshots.count else { return 0 }
        let hash = deterministicHash(snapshots[index])
        return CGFloat(hash % 2000) / 1000.0 - 1.0
    }

    private func deterministicHash(_ snapshot: WalkSnapshot) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshot.id)
        hasher.combine(Int(snapshot.startDate.timeIntervalSince1970))
        hasher.combine(Int(snapshot.distance))
        return abs(hasher.finalize())
    }
}
