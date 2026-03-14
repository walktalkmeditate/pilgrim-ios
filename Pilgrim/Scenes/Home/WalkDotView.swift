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
                .fill(dotColor)
                .frame(width: size, height: size)
                .opacity(opacity)
                .accessibilityLabel(accessibilityText)
        }
        .position(position)
        .onTapGesture { onTap(snapshot.id) }
    }

    var dotSize: CGFloat {
        let minDuration: TimeInterval = 300
        let maxDuration: TimeInterval = 7200
        let clamped = min(max(snapshot.duration, minDuration), maxDuration)
        let normalized = (clamped - minDuration) / (maxDuration - minDuration)
        return minSize + CGFloat(normalized) * (maxSize - minSize)
    }

    private var dotColor: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: "ink",
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
