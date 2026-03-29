import SwiftUI

struct WalkRowView: View {

    let walk: Walk

    var body: some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.stone)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(dateString)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Text(statsString)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.fog)
        }
        .padding(.vertical, Constants.UI.Padding.normal)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: walk.startDate)
    }

    private var statsString: String {
        let distance = Measurement(value: walk.distance, unit: UnitLength.meters)
        let distanceStr = MeasurementFormatter.shortDistance.string(from: distance)
        let duration = walk.activeDuration
        let durationStr = Self.formatDuration(duration)
        return "\(distanceStr) \u{2022} \(durationStr)"
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private extension MeasurementFormatter {
    static let shortDistance: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 2
        return f
    }()
}
