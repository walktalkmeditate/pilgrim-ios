import SwiftUI

struct InkScrollView: View {

    let snapshots: [WalkSnapshot]
    let onTapWalk: (UUID) -> Void

    @State private var previewSnapshot: WalkSnapshot?
    @State private var previewPosition: CGPoint = .zero
    @State private var expandedSnapshot: WalkSnapshot?
    @State private var hapticState = ScrollHapticState()
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { outerGeo in
            ScrollView {
                scrollContent(width: outerGeo.size.width)
            }
            .background(Color.parchment)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, newOffset in
                hapticState.handleScrollOffset(-newOffset, viewportHeight: outerGeo.size.height)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hapticState.currentEvent) { _, new in
                if case .lightDot = new { return true }
                return false
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: hapticState.currentEvent) { _, new in
                if case .heavyDot = new { return true }
                return false
            }
            .sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: hapticState.currentEvent) { _, new in
                if case .milestone = new { return true }
                return false
            }
            .overlay(expandCard)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
                hasAppeared = true
            }
        }
    }

    private func scrollContent(width: CGFloat) -> some View {
        let renderer = CalligraphyPathRenderer(snapshots: snapshots, width: width)
        let positions = renderer.dotPositions()
        let segments = renderer.segmentPaths()

        return ZStack(alignment: .top) {
            Group {
                if !snapshots.isEmpty {
                    journeySummaryHeader(width: width)
                }

                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let segmentOpacity = pathSegmentOpacity(index: segment.index, total: snapshots.count)
                    let segmentColor = pathSegmentColor(index: segment.index)
                    segment.path
                        .fill(segmentColor.opacity(segmentOpacity))
                        .blur(radius: 0.6)
                        .opacity(hasAppeared ? 1 : 0)
                }

            }

            dotsLayer(positions: positions)

            Group {
                dateLabels(positions: positions)
                milestoneMarkers(width: width, positions: positions)

                if snapshots.isEmpty {
                    emptyState(width: width)
                }
            }
        }
        .frame(width: width, height: renderer.totalHeight)
        .onAppear {
            configureHaptics(positions: positions, renderer: renderer)
        }
    }

    // MARK: - Dots layer

    private func dotsLayer(positions: [CalligraphyPathRenderer.DotPosition]) -> some View {
        ForEach(Array(zip(snapshots.indices, snapshots)), id: \.1.id) { index, snapshot in
            if index < positions.count {
                let position = positions[index]
                let opacity = self.dotOpacity(index: index, total: snapshots.count)
                let isNewest = index == 0
                let scenery = self.sceneryForDot(snapshot: snapshot, position: position.center)

                self.dotContent(
                    snapshot: snapshot,
                    position: position.center,
                    opacity: opacity,
                    isNewest: isNewest,
                    sceneryView: scenery
                )
                .opacity(hasAppeared ? 1 : 0)
                .animation(
                    .easeOut(duration: 0.5).delay(Double(index) * 0.03 + 0.3),
                    value: hasAppeared
                )

                self.distanceLabel(snapshot: snapshot, position: position.center, opacity: opacity)
            }
        }
    }

    // MARK: - Journey summary header

    private func journeySummaryHeader(width: CGFloat) -> some View {
        let totalDistance = snapshots.first?.cumulativeDistance ?? 0
        let totalWalks = snapshots.count
        let firstDate = snapshots.last?.startDate ?? Date()
        let months = Calendar.current.dateComponents([.month], from: firstDate, to: Date()).month ?? 0

        return VStack(spacing: 2) {
            Text(Self.formatTotalDistance(totalDistance))
                .font(.system(size: 11, weight: .regular, design: .serif))
                .foregroundColor(.fog.opacity(0.6))

            Text("\(totalWalks) walks · \(max(1, months)) months")
                .font(.system(size: 9, weight: .regular, design: .serif))
                .foregroundColor(.fog.opacity(0.4))
        }
        .position(x: width / 2, y: 16)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.8).delay(0.5), value: hasAppeared)
        .accessibilityLabel("Total: \(Self.formatTotalDistance(totalDistance)), \(totalWalks) walks over \(max(1, months)) months")
    }

    private static func formatTotalDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km walked", meters / 1000)
        }
        return String(format: "%.0f m walked", meters)
    }

    // MARK: - Dot with effects

    private func dotContent(
        snapshot: WalkSnapshot,
        position: CGPoint,
        opacity: Double,
        isNewest: Bool,
        sceneryView: AnyView?
    ) -> some View {
        ZStack {
            WalkDotView(
                snapshot: snapshot,
                position: position,
                opacity: opacity,
                onTap: { id in handleDotTap(snapshot: snapshot, position: position, id: id) },
                sceneryView: sceneryView
            )

            if isNewest {
                newestDotRing(snapshot: snapshot, position: position)
                breathingPulse(snapshot: snapshot, position: position)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    previewSnapshot = snapshot
                    previewPosition = position
                }
        )
    }

    private func handleDotTap(snapshot: WalkSnapshot, position: CGPoint, id: UUID) {
        withAnimation(.spring(duration: 0.3)) {
            if expandedSnapshot?.id == id {
                expandedSnapshot = nil
                onTapWalk(id)
            } else {
                expandedSnapshot = snapshot
            }
        }
    }

    // MARK: - Newest dot ring

    private func newestDotRing(snapshot: WalkSnapshot, position: CGPoint) -> some View {
        let color = dotSeasonalColor(for: snapshot)
        return SonarRingView(color: color)
            .position(position)
    }

    // MARK: - Breathing pulse on newest dot

    private func breathingPulse(snapshot: WalkSnapshot, position: CGPoint) -> some View {
        let color = dotSeasonalColor(for: snapshot)
        return Circle()
            .fill(color.opacity(0.08))
            .frame(width: 50, height: 50)
            .position(position)
            .phaseAnimator([false, true]) { content, phase in
                content
                    .scaleEffect(phase ? 1.3 : 0.9)
                    .opacity(phase ? 0.0 : 0.15)
            } animation: { _ in .easeInOut(duration: 2.5) }
    }

    private func dotSeasonalColor(for snapshot: WalkSnapshot) -> Color {
        let month = Calendar.current.component(.month, from: snapshot.startDate)
        let colorName: String
        switch month {
        case 3...5: colorName = "moss"
        case 6...8: colorName = "rust"
        case 9...11: colorName = "dawn"
        default: colorName = "ink"
        }
        return Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: colorName, intensity: .full, on: snapshot.startDate
        ))
    }

    // MARK: - Expand card

    @ViewBuilder
    private var expandCard: some View {
        if let snapshot = expandedSnapshot {
            VStack {
                Spacer()

                VStack(spacing: 6) {
                    Text(Self.expandDateFormatter.string(from: snapshot.startDate))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.ink)

                    HStack(spacing: 20) {
                        VStack(spacing: 2) {
                            Text(Self.shortDistance(snapshot.distance))
                                .font(Constants.Typography.statValue)
                                .foregroundColor(.ink)
                            Text("distance")
                                .font(.system(size: 9, design: .serif))
                                .foregroundColor(.fog)
                        }

                        Rectangle().fill(Color.fog.opacity(0.2)).frame(width: 0.5, height: 28)

                        VStack(spacing: 2) {
                            Text(Self.formatDuration(snapshot.duration))
                                .font(Constants.Typography.statValue)
                                .foregroundColor(.ink)
                            Text("duration")
                                .font(.system(size: 9, design: .serif))
                                .foregroundColor(.fog)
                        }
                    }

                    Button {
                        let id = snapshot.id
                        expandedSnapshot = nil
                        onTapWalk(id)
                    } label: {
                        Text("View details")
                            .font(.system(size: 11, weight: .medium, design: .serif))
                            .foregroundColor(.stone)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .ink.opacity(0.1), radius: 12, y: -4)
                )
                .padding(.horizontal, Constants.UI.Padding.big)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    withAnimation(.spring(duration: 0.25)) {
                        expandedSnapshot = nil
                    }
                }
            }
        }
    }

    private static let expandDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d yyyy · h:mm a"
        return f
    }()

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return String(format: "%d:%02d", h, m) }
        return "\(m)m"
    }

    // MARK: - Dot opacity

    private func dotOpacity(index: Int, total: Int) -> Double {
        guard total > 1 else { return 1.0 }
        let normalized = Double(index) / Double(total - 1)
        return 1.0 - normalized * 0.5
    }

    // MARK: - Scenery

    private func sceneryForDot(snapshot: WalkSnapshot, position: CGPoint) -> AnyView? {
        guard let placement = SceneryGenerator.scenery(for: snapshot) else {
            return nil
        }

        let tintColor = Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: placement.tintColorName,
            intensity: .full,
            on: snapshot.startDate
        ))

        let baseSize: CGFloat = 32
        let sizeVariation = CGFloat(abs(snapshot.id.hashValue % 20)) / 20.0
        let size = baseSize + sizeVariation * 24

        let xOffset: CGFloat = placement.side == .left ? -40 - size / 2 : 40 + size / 2
        let sceneryPosition = CGPoint(
            x: position.x + xOffset + placement.offset,
            y: position.y - 4
        )

        return AnyView(
            SceneryItemView(
                type: placement.type,
                tintColor: tintColor,
                size: size,
                walkDate: snapshot.startDate
            )
            .position(sceneryPosition)
            .visualEffect { content, proxy in
                let frame = proxy.frame(in: .global)
                let screenMid = UIScreen.main.bounds.height / 2
                let distFromCenter = (frame.midY - screenMid) / screenMid
                return content.offset(x: distFromCenter * 8)
            }
            .accessibilityHidden(true)
        )
    }

    // MARK: - Path rendering

    private func pathSegmentOpacity(index: Int, total: Int) -> Double {
        guard total > 1 else { return 0.35 }
        let normalized = Double(index) / Double(total - 1)
        return 0.35 - normalized * 0.2
    }

    private func pathSegmentColor(index: Int) -> Color {
        guard index < snapshots.count else { return .ink }
        let month = Calendar.current.component(.month, from: snapshots[index].startDate)
        let colorName: String
        switch month {
        case 3...5: colorName = "moss"
        case 6...8: colorName = "rust"
        case 9...11: colorName = "dawn"
        default: colorName = "ink"
        }
        return Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: colorName,
            intensity: .moderate,
            on: snapshots[index].startDate
        ))
    }

    // MARK: - Distance labels

    private func distanceLabel(snapshot: WalkSnapshot, position: CGPoint, opacity: Double) -> some View {
        let labelX = position.x > UIScreen.main.bounds.width / 2
            ? position.x - 32
            : position.x + 32

        return Text(Self.shortDistance(snapshot.distance))
            .font(.system(size: 9, weight: .regular, design: .serif))
            .foregroundColor(.fog.opacity(0.5))
            .position(x: labelX, y: position.y + 14)
            .opacity(opacity * 0.7)
            .accessibilityHidden(true)
    }

    private static func shortDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }

    // MARK: - Date labels

    private func dateLabels(positions: [CalligraphyPathRenderer.DotPosition]) -> some View {
        let labels = computeDateLabels(positions: positions)
        return ForEach(labels, id: \.id) { label in
            Text(label.text)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.5))
                .position(x: label.x, y: label.y)
                .accessibilityHidden(true)
        }
    }

    private struct DateLabel: Identifiable {
        let id: Int
        let text: String
        let x: CGFloat
        let y: CGFloat
    }

    private func computeDateLabels(positions: [CalligraphyPathRenderer.DotPosition]) -> [DateLabel] {
        guard snapshots.count >= 2 else { return [] }

        var labels: [DateLabel] = []
        var lastMonthYear = ""

        for (index, snapshot) in snapshots.enumerated() {
            guard index < positions.count else { continue }
            let calendar = Calendar.current
            let month = calendar.component(.month, from: snapshot.startDate)
            let year = calendar.component(.year, from: snapshot.startDate)
            let key = "\(year)-\(month)"

            if key != lastMonthYear {
                lastMonthYear = key
                let pos = positions[index]
                let labelX: CGFloat = pos.center.x > 200 ? 36 : UIScreen.main.bounds.width - 36

                labels.append(DateLabel(
                    id: index,
                    text: Self.monthFormatter.string(from: snapshot.startDate),
                    x: labelX,
                    y: pos.yOffset
                ))
            }
        }

        return labels
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    // MARK: - Empty state

    private func emptyState(width: CGFloat) -> some View {
        let renderer = CalligraphyPathRenderer(snapshots: [], width: width)
        let positions = renderer.dotPositions()
        let center = positions.first?.center ?? CGPoint(x: width / 2, y: 80)

        return ZStack {
            renderer.emptyStatePath()
                .fill(Color.ink.opacity(0.2))

            VStack(spacing: Constants.UI.Padding.small) {
                Circle()
                    .fill(Color.stone)
                    .frame(width: 14, height: 14)

                Text("Begin")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            .position(center)
        }
    }

    // MARK: - Milestones

    private func milestoneMarkers(width: CGFloat, positions: [CalligraphyPathRenderer.DotPosition]) -> some View {
        let milestones = computeMilestonePositions(positions: positions)
        return ForEach(milestones, id: \.distance) { milestone in
            MilestoneMarkerView(width: width, distance: milestone.distance)
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

    // MARK: - Haptics

    private func configureHaptics(
        positions: [CalligraphyPathRenderer.DotPosition],
        renderer: CalligraphyPathRenderer
    ) {
        hapticState.dotPositions = positions.map { $0.yOffset }

        hapticState.dotSizes = snapshots.map { snap in
            let view = WalkDotView(
                snapshot: snap,
                position: .zero,
                opacity: 1,
                onTap: { _ in },
                sceneryView: nil
            )
            return view.dotSize
        }

        let milestonePositions = computeMilestonePositions(positions: positions)
        hapticState.milestonePositions = milestonePositions.map { $0.yPosition }
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

private struct SonarRingView: View {
    let color: Color
    @State private var scale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0.5

    var body: some View {
        Circle()
            .stroke(color.opacity(ringOpacity), lineWidth: 1.5)
            .frame(width: 28, height: 28)
            .scaleEffect(scale)
            .onAppear { startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            scale = 2.0
            ringOpacity = 0
        }
    }
}
