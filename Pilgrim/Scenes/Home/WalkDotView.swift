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
            named: colorName,
            intensity: .full,
            on: snapshot.startDate
        ))
    }

    private var accessibilityText: String {
        let dateStr = Self.dateFormatter.string(from: snapshot.startDate)
        let distance = Measurement(value: snapshot.distance, unit: UnitLength.meters)
        let distanceStr = Self.measurementFormatter.string(from: distance)
        let duration = Self.formatDuration(snapshot.duration)
        return "Walk on \(dateStr), \(distanceStr), \(duration)"
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

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
