import SwiftUI

struct PracticeSummaryHeader: View {
    let walkCount: Int
    let totalDistanceMeters: Double
    let totalMeditationSeconds: TimeInterval
    var firstWalkDate: Date?

    @State private var statPhase = 0

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.xs) {
                Text(seasonLabel)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Image(systemName: seasonSymbol)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .opacity(0.3)
            }

            if walkCount > 0 {
                Text(currentStatLine)
                    .font(Constants.Typography.body)
                    .foregroundColor(.stone)
                    .contentTransition(.numericText())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            statPhase = (statPhase + 1) % 3
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.UI.Padding.big)
    }

    // MARK: - Cycling Stats

    private var currentStatLine: String {
        switch statPhase {
        case 1:
            return meditationStatLine
        case 2:
            return walkingSinceLine
        default:
            return statsLine
        }
    }

    private var statsLine: String {
        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        let distKm = totalDistanceMeters / 1000
        let dist = isImperial ? distKm * 0.621371 : distKm
        let unit = isImperial ? "mi" : "km"
        return "\(walkCount) walks \u{00B7} \(String(format: "%.0f", dist)) \(unit)"
    }

    private var meditationStatLine: String {
        guard totalMeditationSeconds > 0 else { return "No meditation yet" }
        let hours = Int(totalMeditationSeconds) / 3600
        let minutes = (Int(totalMeditationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m in stillness"
        }
        return "\(minutes)m in stillness"
    }

    private var walkingSinceLine: String {
        guard let date = firstWalkDate else { return statsLine }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return "Walking since \(formatter.string(from: date))"
    }

    // MARK: - Season

    private var seasonLabel: String {
        let hemisphereHint: Double = (UserPreferences.hemisphereOverride.value ?? 1) >= 0 ? 1 : -1
        let season = SealTimeHelpers.season(for: Date(), latitude: hemisphereHint)
        let year = Calendar.current.component(.year, from: Date())
        return "\(season) \(year)"
    }

    private var seasonSymbol: String {
        let hemisphereHint: Double = (UserPreferences.hemisphereOverride.value ?? 1) >= 0 ? 1 : -1
        let season = SealTimeHelpers.season(for: Date(), latitude: hemisphereHint)
        switch season {
        case "Spring": return "leaf.fill"
        case "Summer": return "sun.max.fill"
        case "Autumn": return "wind"
        default:       return "snowflake"
        }
    }
}
