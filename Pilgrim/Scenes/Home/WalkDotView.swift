import SwiftUI

struct WalkDotView: View {

    let snapshot: WalkSnapshot
    let position: CGPoint
    let opacity: Double
    let onTap: (UUID) -> Void
    let sceneryView: AnyView?

    private let minSize: CGFloat = 8
    private let maxSize: CGFloat = 22

    var body: some View {
        let size = dotSize

        ZStack {
            if let scenery = sceneryView {
                scenery
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [dotColor.opacity(0.15), .clear],
                        center: .center,
                        startRadius: size * 0.5,
                        endRadius: size * 1.8
                    )
                )
                .frame(width: size * 3.5, height: size * 3.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [dotColor, dotColor.opacity(0.7)],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: size * 0.6
                    )
                )
                .frame(width: size, height: size)
                .opacity(opacity)
                .shadow(color: .ink.opacity(0.15), radius: 2, x: 1, y: 2)

            faviconOverlay(size: size)

            activityArcs(size: size)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.3), .clear],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.4
                    )
                )
                .frame(width: size * 0.7, height: size * 0.7)
                .opacity(opacity * 0.5)
                .offset(x: -size * 0.08, y: -size * 0.08)

        }
        .position(position)
        .onTapGesture { onTap(snapshot.id) }
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Favicon overlay

    @ViewBuilder
    private func faviconOverlay(size: CGFloat) -> some View {
        if let raw = snapshot.favicon, let fav = WalkFavicon(rawValue: raw) {
            Image(systemName: fav.icon)
                .font(.system(size: size * 0.4))
                .bold()
                .foregroundColor(.parchment)
                .shadow(color: .ink.opacity(0.4), radius: 0.5, x: 0, y: 0.5)
                .frame(width: size, height: size)
                .opacity(opacity)
        }
    }

    // MARK: - Activity arcs

    @ViewBuilder
    private func activityArcs(size: CGFloat) -> some View {
        let total = snapshot.duration
        if total > 0 {
            let talkFrac = snapshot.talkDuration / total
            let meditateFrac = snapshot.meditateDuration / total
            let ringSize = size + 5

            ZStack {
                if talkFrac > 0.01 {
                    Circle()
                        .trim(from: 0, to: talkFrac)
                        .stroke(Color.rust.opacity(0.7), lineWidth: 2)
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))
                }

                if meditateFrac > 0.01 {
                    Circle()
                        .trim(from: talkFrac, to: talkFrac + meditateFrac)
                        .stroke(Color.dawn.opacity(0.7), lineWidth: 2)
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))
                }
            }
            .opacity(opacity)
        }
    }

    var dotSize: CGFloat {
        let minDuration: TimeInterval = 300
        let maxDuration: TimeInterval = 7200
        let clamped = min(max(snapshot.duration, minDuration), maxDuration)
        let normalized = (clamped - minDuration) / (maxDuration - minDuration)
        return minSize + CGFloat(normalized) * (maxSize - minSize)
    }

    private var dotColor: Color {
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

    private var accessibilityText: String {
        let dateStr = Self.dateFormatter.string(from: snapshot.startDate)
        let distance = Measurement(value: snapshot.distance, unit: UnitLength.meters)
        let distanceStr = Self.measurementFormatter.string(from: distance)
        let duration = Self.formatDuration(snapshot.duration)
        var text = "Walk on \(dateStr), \(distanceStr), \(duration)"
        if snapshot.hasTalk { text += ", \(Self.formatDuration(snapshot.talkDuration)) talking" }
        if snapshot.hasMeditate { text += ", \(Self.formatDuration(snapshot.meditateDuration)) meditating" }
        return text
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let measurementFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
