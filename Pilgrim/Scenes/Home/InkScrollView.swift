import CoreLocation
import SwiftUI

struct InkScrollView: View {

    let snapshots: [WalkSnapshot]
    let onTapWalk: (UUID) -> Void

    @State private var previewSnapshot: WalkSnapshot?
    @State private var previewPosition: CGPoint = .zero
    @State private var expandedSnapshot: WalkSnapshot?
    @State private var expandedCelestial: CelestialSnapshot?
    @State private var hapticState = ScrollHapticState()
    @State private var hasAppeared = false
    @State private var statMode: StatMode = .walks

    private enum StatMode: CaseIterable {
        case walks, talks, meditations
    }

    var body: some View {
        GeometryReader { outerGeo in
            ScrollView {
                scrollContent(width: outerGeo.size.width, height: outerGeo.size.height)
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
            DispatchQueue.main.async {
                hasAppeared = true
            }
        }
    }

    private func scrollContent(width: CGFloat, height: CGFloat) -> some View {
        let renderer = CalligraphyPathRenderer(snapshots: snapshots, width: width)
        let positions = renderer.dotPositions()
        let segments = renderer.segmentPaths()

        return ZStack(alignment: .top) {
            turningBanner

            Group {
                if !snapshots.isEmpty {
                    journeySummaryHeader(width: width, topOffset: currentTurning != nil ? 64 : 0)
                }

                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let segmentOpacity = pathSegmentOpacity(index: segment.index, total: snapshots.count)
                    let segmentColor = pathSegmentColor(index: segment.index)
                    segment.path
                        .fill(segmentColor.opacity(segmentOpacity))
                        .blur(radius: 0.6)
                        .opacity(hasAppeared ? 1 : 0)
                        .animation(.easeOut(duration: 1.2).delay(0.2), value: hasAppeared)
                }

            }

            dotsLayer(positions: positions, viewportWidth: width, viewportHeight: height)

            Group {
                dateLabels(positions: positions, viewportWidth: width)
                turningMarkers(positions: positions)
                lunarMarkers(positions: positions, viewportWidth: width)
                milestoneMarkers(width: width, positions: positions)

                if snapshots.isEmpty {
                    emptyState(width: width)
                }
            }
            .transaction { $0.animation = nil }
        }
        .frame(width: width, height: renderer.totalHeight)
        .onAppear {
            configureHaptics(positions: positions, renderer: renderer)
        }
    }

    // MARK: - Dots layer

    private func dotsLayer(positions: [CalligraphyPathRenderer.DotPosition], viewportWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        ForEach(Array(zip(snapshots.indices, snapshots)), id: \.1.id) { index, snapshot in
            if index < positions.count {
                let position = positions[index]
                let opacity = self.dotOpacity(index: index, total: snapshots.count)
                let isNewest = index == 0
                let scenery = self.sceneryForDot(snapshot: snapshot, position: position.center, viewportHeight: viewportHeight)

                self.dotContent(
                    snapshot: snapshot,
                    position: position.center,
                    opacity: opacity,
                    sceneryView: scenery,
                    isNewest: isNewest
                )
                .opacity(hasAppeared ? 1 : 0)
                .animation(
                    .easeOut(duration: 0.5).delay(Double(index) * 0.03 + 0.3),
                    value: hasAppeared
                )

                self.distanceLabel(snapshot: snapshot, position: position.center, opacity: opacity, viewportWidth: viewportWidth)
            }
        }
    }

    // MARK: - Journey summary header (tappable cycling)

    private func journeySummaryHeader(width: CGFloat, topOffset: CGFloat = 0) -> some View {
        let totalDistance = snapshots.first?.cumulativeDistance ?? 0
        let totalWalks = snapshots.count
        let firstDate = snapshots.last?.startDate ?? Date()
        let months = max(1, Calendar.current.dateComponents([.month], from: firstDate, to: Date()).month ?? 0)
        let totalTalk = snapshots.reduce(0) { $0 + $1.talkDuration }
        let totalMeditate = snapshots.reduce(0) { $0 + $1.meditateDuration }
        let talkers = snapshots.filter { $0.hasTalk }.count
        let meditators = snapshots.filter { $0.hasMeditate }.count

        return VStack(spacing: 2) {
            Group {
                switch statMode {
                case .walks:
                    Text(Self.formatTotalDistance(totalDistance))
                case .talks:
                    Text(WalkDotView.formatDuration(totalTalk) + " talked")
                case .meditations:
                    Text(WalkDotView.formatDuration(totalMeditate) + " meditated")
                }
            }
            .font(Constants.Typography.body)
            .foregroundColor(.stone)
            .contentTransition(.numericText())

            Group {
                switch statMode {
                case .walks:
                    Text("\(totalWalks) walks · \(months) months")
                case .talks:
                    Text("\(talkers) walks with talk")
                case .meditations:
                    Text("\(meditators) walks with meditation")
                }
            }
            .font(Constants.Typography.caption)
            .foregroundColor(.fog.opacity(0.7))
            .contentTransition(.numericText())
        }
        .position(x: width / 2, y: 16 + topOffset)
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.8).delay(0.5), value: hasAppeared)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                let modes = StatMode.allCases
                let idx = modes.firstIndex(of: statMode) ?? 0
                statMode = modes[(idx + 1) % modes.count]
            }
        }
    }

    private static func formatTotalDistance(_ meters: Double) -> String {
        let isMiles = UserPreferences.distanceMeasurementType.safeValue == .miles
        if isMiles {
            let miles = meters / 1609.344
            if miles >= 1 {
                return String(format: "%.1f mi walked", miles)
            }
            let feet = meters * 3.28084
            return String(format: "%.0f ft walked", feet)
        }
        if meters >= 1000 {
            return String(format: "%.1f km walked", meters / 1000)
        }
        return String(format: "%.0f m walked", meters)
    }

    // MARK: - Turning day banner

    private var currentTurning: SeasonalMarker? {
        TurningDayService.turningForToday()
    }

    @ViewBuilder
    private var turningBanner: some View {
        if let turning = currentTurning,
           let text = turning.bannerText,
           let kanji = turning.kanji {
            HStack(spacing: 8) {
                Text(text)
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
                Text("·")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog.opacity(0.5))
                if let color = turning.color {
                    Text(kanji)
                        .font(Constants.Typography.body)
                        .foregroundColor(color)
                } else {
                    Text(kanji)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Constants.UI.Padding.big)
            .padding(.bottom, Constants.UI.Padding.small)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(text). \(turning.name).")
        }
    }

    // MARK: - Dot with effects

    private func dotContent(
        snapshot: WalkSnapshot,
        position: CGPoint,
        opacity: Double,
        sceneryView: AnyView?,
        isNewest: Bool = false
    ) -> some View {
        WalkDotView(
            snapshot: snapshot,
            position: position,
            opacity: opacity,
            isNewest: isNewest,
            onTap: { id in handleDotTap(snapshot: snapshot, position: position, id: id) },
            sceneryView: sceneryView
        )
        .accessibilityIdentifier("walk_dot_\(snapshot.id.uuidString.prefix(8))")
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
                expandedCelestial = nil
            } else {
                expandedSnapshot = snapshot
                if UserPreferences.celestialAwarenessEnabled.value {
                    let system = ZodiacSystem(rawValue: UserPreferences.zodiacSystem.value) ?? .tropical
                    expandedCelestial = CelestialCalculator.snapshot(for: snapshot.startDate, system: system)
                } else {
                    expandedCelestial = nil
                }
            }
        }
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
            let seasonColor = dotSeasonalColor(for: snapshot)

            VStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.25)) { expandedSnapshot = nil }
                    }

                VStack(spacing: 10) {
                    HStack {
                        FootprintShape()
                            .fill(seasonColor.opacity(0.3))
                            .frame(width: 12, height: 18)

                        if let raw = snapshot.favicon, let fav = WalkFavicon(rawValue: raw) {
                            Image(systemName: fav.icon)
                                .font(Constants.Typography.caption)
                                .foregroundColor(seasonColor)
                        }

                        Text(Self.expandDateFormatter.string(from: snapshot.startDate))
                            .font(Constants.Typography.annotation)
                            .foregroundColor(.ink)

                        Spacer()

                        if snapshot.isShared {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                                .foregroundColor(.stone)
                                .opacity(0.5)
                        }

                        if let celestial = expandedCelestial {
                            let moonSign = celestial.system == .tropical
                                ? celestial.position(for: .moon)?.tropical.sign
                                : celestial.position(for: .moon)?.sidereal.sign
                            if let moonSign {
                                Text("\(celestial.planetaryHour.planet.symbol)\(moonSign.symbol)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.fog)
                            }
                        }

                        if let condStr = snapshot.weatherCondition,
                           let cond = WeatherCondition(rawValue: condStr) {
                            Image(systemName: cond.icon)
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }

                    Rectangle()
                        .fill(seasonColor.opacity(0.15))
                        .frame(height: 1)

                    HStack(spacing: 0) {
                        expandStat(value: Self.shortDistance(snapshot.distance), label: "distance")
                        Spacer()
                        expandStat(value: WalkDotView.formatDuration(snapshot.duration), label: "duration")
                        Spacer()
                        expandStat(value: Self.formatPace(snapshot.averagePace), label: "pace")
                    }

                    miniActivityBar(snapshot: snapshot)

                    activityPills(snapshot: snapshot)

                    Button {
                        let id = snapshot.id
                        withAnimation(.spring(duration: 0.25)) { expandedSnapshot = nil }
                        onTapWalk(id)
                    } label: {
                        Text("View details \(Image(systemName: "arrow.right"))")
                            .font(Constants.Typography.annotation)
                            .foregroundColor(.parchment)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.stone.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .accessibilityIdentifier("walk_details_button")
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(seasonColor.opacity(0.10))
                        )
                        .shadow(color: .ink.opacity(0.1), radius: 12, y: -4)
                )
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func expandStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(Constants.Typography.micro)
                .foregroundColor(.fog)
        }
    }

    private func miniActivityBar(snapshot: WalkSnapshot) -> some View {
        let total = max(1, snapshot.duration)
        let walkFrac = snapshot.walkOnlyDuration / total
        let talkFrac = snapshot.talkDuration / total
        let meditateFrac = snapshot.meditateDuration / total

        return GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 1) {
                if walkFrac > 0.01 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.moss.opacity(0.5))
                        .frame(width: w * walkFrac)
                }
                if talkFrac > 0.01 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.rust.opacity(0.6))
                        .frame(width: w * talkFrac)
                }
                if meditateFrac > 0.01 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.dawn.opacity(0.6))
                        .frame(width: w * meditateFrac)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }

    private func activityPills(snapshot: WalkSnapshot) -> some View {
        HStack(spacing: 8) {
            activityPill(color: .moss, duration: snapshot.walkOnlyDuration, label: "walk")

            if snapshot.hasTalk {
                activityPill(color: .rust, duration: snapshot.talkDuration, label: "talk")
            }

            if snapshot.hasMeditate {
                activityPill(color: .dawn, duration: snapshot.meditateDuration, label: "meditate")
            }

            Spacer()
        }
    }

    private func activityPill(color: Color, duration: TimeInterval, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(WalkDotView.formatDuration(duration)) \(label)")
                .font(Constants.Typography.micro)
                .foregroundColor(.fog)
        }
    }

    private static func formatPace(_ pace: Double) -> String {
        guard pace > 0 else { return "—" }
        let isMiles = UserPreferences.distanceMeasurementType.safeValue == .miles
        let adjustedPace = isMiles ? pace * 1.60934 : pace
        let minutes = Int(adjustedPace) / 60
        let seconds = Int(adjustedPace) % 60
        let unitLabel = isMiles ? "/mi" : "/km"
        return String(format: "%d:%02d%@", minutes, seconds, unitLabel)
    }

    private static let expandDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    // MARK: - Dot opacity

    private func dotOpacity(index: Int, total: Int) -> Double {
        guard total > 1 else { return 1.0 }
        let normalized = Double(index) / Double(total - 1)
        return 1.0 - normalized * 0.5
    }

    // MARK: - Weather mood

    private static func weatherAdjustedColor(_ color: Color, condition: String?) -> Color {
        guard let condStr = condition,
              let cond = WeatherCondition(rawValue: condStr) else { return color }

        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        switch cond {
        case .clear:
            h += 0.02
            b = min(b * 1.05, 1)
        case .partlyCloudy:
            break
        case .overcast:
            s *= 0.85
            b *= 0.95
        case .lightRain:
            h -= 0.01
            b *= 0.88
        case .heavyRain:
            h -= 0.02
            b *= 0.80
        case .thunderstorm:
            s *= 0.7
            b *= 0.75
        case .snow:
            h += 0.03
            b = min(b * 1.05, 1)
            s *= 0.85
        case .fog:
            s *= 0.6
            b *= 0.9
        case .wind:
            break
        case .haze:
            h += 0.02
            s *= 0.85
        }

        return Color(hue: Double((h + 1).truncatingRemainder(dividingBy: 1)),
                      saturation: Double(max(0, min(s, 1))),
                      brightness: Double(max(0, min(b, 1))),
                      opacity: Double(a))
    }

    // MARK: - Scenery

    private func sceneryForDot(snapshot: WalkSnapshot, position: CGPoint, viewportHeight: CGFloat) -> AnyView? {
        guard let placement = SceneryGenerator.scenery(for: snapshot) else {
            return nil
        }

        let baseTint = Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: placement.tintColorName,
            intensity: .full,
            on: snapshot.startDate
        ))
        let tintColor = Self.weatherAdjustedColor(baseTint, condition: snapshot.weatherCondition)

        let baseSize: CGFloat = 32
        var h: UInt64 = 14695981039346656037
        withUnsafeBytes(of: snapshot.id) { $0.forEach { h = (h ^ UInt64($0)) &* 1099511628211 } }
        let sizeVariation = CGFloat(h % 20) / 20.0
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
                let screenMid = viewportHeight / 2
                let distFromCenter = (frame.midY - screenMid) / screenMid
                return content.offset(x: distFromCenter * 8)
            }
            .accessibilityHidden(true)
        )
    }

    // MARK: - Path rendering

    private func turningColorForSegment(index: Int) -> Color? {
        guard index >= 0 && index < snapshots.count else { return nil }
        let snapshot = snapshots[index]
        return TurningDayService.turning(for: snapshot.startDate, hemisphere: .current)?.color
    }

    private func pathSegmentOpacity(index: Int, total: Int) -> Double {
        guard total > 1 else { return 0.35 }
        let normalized = Double(index) / Double(total - 1)
        return 0.35 - normalized * 0.2
    }

    private func pathSegmentColor(index: Int) -> Color {
        if let turningColor = turningColorForSegment(index: index) {
            return turningColor.opacity(0.85)
        }
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

    private func distanceLabel(snapshot: WalkSnapshot, position: CGPoint, opacity: Double, viewportWidth: CGFloat) -> some View {
        let labelX = position.x > viewportWidth / 2
            ? position.x - 32
            : position.x + 32

        return Text(Self.shortDistance(snapshot.distance))
            .font(Constants.Typography.micro)
            .foregroundColor(.fog.opacity(0.5))
            .position(x: labelX, y: position.y + 14)
            .opacity(opacity * 0.7)
            .accessibilityHidden(true)
    }

    private static func shortDistance(_ meters: Double) -> String {
        let isMiles = UserPreferences.distanceMeasurementType.safeValue == .miles
        if isMiles {
            let miles = meters / 1609.344
            if miles >= 1 {
                return String(format: "%.1fmi", miles)
            }
            let feet = meters * 3.28084
            return String(format: "%.0fft", feet)
        }
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }

    // MARK: - Date labels

    private func dateLabels(positions: [CalligraphyPathRenderer.DotPosition], viewportWidth: CGFloat) -> some View {
        let labels = computeDateLabels(positions: positions, viewportWidth: viewportWidth)
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

    private func computeDateLabels(positions: [CalligraphyPathRenderer.DotPosition], viewportWidth: CGFloat) -> [DateLabel] {
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
                let labelX: CGFloat = pos.center.x > viewportWidth / 2 ? 36 : viewportWidth - 36

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
        f.setLocalizedDateFormatFromTemplate("MMM")
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
                let prevCumulative = i > 0 ? snapshots[i - 1].cumulativeDistance : 0
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
                isNewest: false,
                onTap: { _ in },
                sceneryView: nil
            )
            return view.dotSize
        }

        let milestonePositions = computeMilestonePositions(positions: positions)
        hapticState.milestonePositions = milestonePositions.map { $0.yPosition }
    }

}
