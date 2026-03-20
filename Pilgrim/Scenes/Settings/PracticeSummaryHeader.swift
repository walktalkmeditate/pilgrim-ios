import SwiftUI

struct PracticeSummaryHeader: View {
    let walkCount: Int
    let totalDistanceMeters: Double
    let totalMeditationSeconds: TimeInterval

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text(seasonLabel)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)

            if walkCount > 0 {
                Text(statsLine)
                    .font(Constants.Typography.body)
                    .foregroundColor(.stone)

                if totalMeditationSeconds > 60 {
                    Text(meditationLine)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.UI.Padding.big)
    }

    private var seasonLabel: String {
        let season = SealTimeHelpers.season(for: Date(), latitude: 0)
        let year = Calendar.current.component(.year, from: Date())
        return "\(season) \(year)"
    }

    private var statsLine: String {
        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        let distKm = totalDistanceMeters / 1000
        let dist = isImperial ? distKm * 0.621371 : distKm
        let unit = isImperial ? "mi" : "km"
        return "\(walkCount) walks \u{00B7} \(String(format: "%.0f", dist)) \(unit)"
    }

    private var meditationLine: String {
        let hours = Int(totalMeditationSeconds) / 3600
        let minutes = (Int(totalMeditationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m meditated"
        }
        return "\(minutes) min meditated"
    }
}
