import SwiftUI

struct InkScrollView: View {

    let snapshots: [WalkSnapshot]
    let onTapWalk: (UUID) -> Void

    @State private var previewSnapshot: WalkSnapshot?
    @State private var previewPosition: CGPoint = .zero
    @StateObject private var hapticEngine = ScrollHapticEngineModel()

    var body: some View {
        GeometryReader { outerGeo in
            ScrollView {
                ZStack(alignment: .top) {
                    agingGradient

                    scrollContent(width: outerGeo.size.width)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("inkScroll")).minY
                                )
                            }
                        )
                }
            }
            .coordinateSpace(name: "inkScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                hapticEngine.engine.handleScrollOffset(offset, viewportHeight: outerGeo.size.height)
            }
            .overlay(previewLabel)
        }
    }

    private func scrollContent(width: CGFloat) -> some View {
        let renderer = CalligraphyPathRenderer(snapshots: snapshots, width: width)
        let positions = renderer.dotPositions()

        return ZStack(alignment: .top) {
            renderer.path()
                .fill(Color.ink.opacity(0.15))

            ForEach(Array(zip(snapshots.indices, snapshots)), id: \.1.id) { index, snapshot in
                if index < positions.count {
                    let position = positions[index]
                    let opacity = dotOpacity(index: index, total: snapshots.count)

                    let scenery = sceneryForDot(snapshot: snapshot, position: position.center)

                    WalkDotView(
                        snapshot: snapshot,
                        position: position.center,
                        opacity: opacity,
                        onTap: onTapWalk,
                        sceneryView: scenery
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in
                                previewSnapshot = snapshot
                                previewPosition = position.center
                            }
                    )
                }
            }

            milestoneMarkers(width: width, positions: positions)

            if snapshots.isEmpty {
                emptyState(width: width)
            }
        }
        .frame(width: width, height: renderer.totalHeight)
        .onAppear {
            configureHaptics(positions: positions, renderer: renderer)
        }
    }

    private func emptyState(width: CGFloat) -> some View {
        let renderer = CalligraphyPathRenderer(snapshots: [], width: width)
        let positions = renderer.dotPositions()
        let center = positions.first?.center ?? CGPoint(x: width / 2, y: 40)

        return VStack(spacing: Constants.UI.Padding.small) {
            Circle()
                .fill(Color.stone)
                .frame(width: 14, height: 14)

            Text("Begin")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
        .position(center)
    }

    private var agingGradient: some View {
        LinearGradient(
            colors: [.clear, Color.dawn.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var previewLabel: some View {
        if let snapshot = previewSnapshot {
            VStack(spacing: 2) {
                Text(Self.previewDateFormatter.string(from: snapshot.startDate))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.ink)
                Text(Self.formatDistance(snapshot.distance))
                    .font(Constants.Typography.statLabel)
                    .foregroundColor(.fog)
            }
            .padding(.horizontal, Constants.UI.Padding.small)
            .padding(.vertical, Constants.UI.Padding.xs)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
                    .fill(Color.parchment)
                    .shadow(color: .ink.opacity(0.1), radius: 4, y: 2)
            )
            .position(x: previewPosition.x, y: previewPosition.y - 40)
            .onTapGesture { previewSnapshot = nil }
            .transition(.opacity)
        }
    }

    private func dotOpacity(index: Int, total: Int) -> Double {
        guard total > 1 else { return 1.0 }
        let normalized = Double(index) / Double(total - 1)
        return 1.0 - normalized * 0.6
    }

    private func sceneryForDot(snapshot: WalkSnapshot, position: CGPoint) -> AnyView? {
        guard let placement = SceneryGenerator.scenery(for: snapshot) else {
            return nil
        }

        let tintColor = Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: placement.tintColorName,
            intensity: .full,
            on: snapshot.startDate
        ))

        let xOffset: CGFloat = placement.side == .left ? -30 : 30
        let sceneryPosition = CGPoint(
            x: position.x + xOffset + placement.offset,
            y: position.y - 5
        )

        let size: CGFloat = 24

        return AnyView(
            placement.shape
                .fill(tintColor.opacity(0.5))
                .frame(width: size, height: size)
                .position(sceneryPosition)
                .accessibilityHidden(true)
        )
    }

    private func milestoneMarkers(width: CGFloat, positions: [CalligraphyPathRenderer.DotPosition]) -> some View {
        let milestones = computeMilestonePositions(positions: positions)
        return ForEach(milestones, id: \.distance) { milestone in
            MilestoneMarkerView(width: width)
                .position(x: width / 2, y: milestone.yPosition)
        }
    }

    private struct MilestonePosition: Equatable {
        let distance: Double
        let yPosition: CGFloat
    }

    private func computeMilestonePositions(positions: [CalligraphyPathRenderer.DotPosition]) -> [MilestonePosition] {
        guard snapshots.count >= 2 else { return [] }

        let thresholds = milestoneThresholds()
        var results: [MilestonePosition] = []

        let totalDistance = snapshots.first?.cumulativeDistance ?? 0

        for threshold in thresholds {
            guard threshold <= totalDistance else { continue }

            for i in 0..<snapshots.count {
                let snap = snapshots[i]
                let prevCumulative = i > 0 ? snapshots[i - 1].cumulativeDistance - snapshots[i - 1].distance : 0
                let currentCumulative = snap.cumulativeDistance

                if prevCumulative < threshold && currentCumulative >= threshold, i < positions.count {
                    results.append(MilestonePosition(
                        distance: threshold,
                        yPosition: positions[i].yOffset
                    ))
                    break
                }
            }
        }

        return results
    }

    private func milestoneThresholds() -> [Double] {
        var thresholds: [Double] = [100_000, 500_000, 1_000_000]
        var next = 2_000_000.0
        while next <= 100_000_000 {
            thresholds.append(next)
            next += 1_000_000
        }
        return thresholds
    }

    private func configureHaptics(
        positions: [CalligraphyPathRenderer.DotPosition],
        renderer: CalligraphyPathRenderer
    ) {
        hapticEngine.engine.dotPositions = positions.map { $0.yOffset }

        let dotViewHelper = WalkDotView(
            snapshot: WalkSnapshot(id: UUID(), startDate: Date(), distance: 0, duration: 0, averagePace: 0, cumulativeDistance: 0),
            position: .zero,
            opacity: 1,
            onTap: { _ in },
            sceneryView: nil
        )
        hapticEngine.engine.dotSizes = snapshots.map { snap in
            let view = WalkDotView(
                snapshot: snap,
                position: .zero,
                opacity: 1,
                onTap: { _ in },
                sceneryView: nil
            )
            return view.dotSize
        }
        _ = dotViewHelper

        let milestonePositions = computeMilestonePositions(positions: positions)
        hapticEngine.engine.milestonePositions = milestonePositions.map { $0.yPosition }

        hapticEngine.engine.prepare()
    }

    private static let previewDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func formatDistance(_ meters: Double) -> String {
        let distance = Measurement(value: meters, unit: UnitLength.meters)
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 1
        return f.string(from: distance)
    }
}

private class ScrollHapticEngineModel: ObservableObject {
    let engine = ScrollHapticEngine()
}
