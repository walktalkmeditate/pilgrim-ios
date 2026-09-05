import CoreLocation
import SwiftUI

enum StageMorningCardModel {

    /// "24 km · 1,400 m up · 7 to 9 hours · hard", in the walker's own unit —
    /// the same line the route screen's stage list shows, from the same
    /// formatter (`WayStageFacts`, Task 8). The two must not drift.
    static func factsLine(for stage: WayStage) -> String {
        WayStageFacts.line(distanceKm: stage.distanceKm, gainMeters: stage.gainMeters,
                           hours: stage.hours, difficulty: stage.difficulty)
    }

    /// "clear, 9°". Nothing at all when the fetch found nothing — a stage's
    /// words do not need weather to stand.
    static func weatherLine(_ snapshot: WeatherSnapshot?) -> String? {
        guard let snapshot else { return nil }
        let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        return "\(snapshot.condition.label.lowercased()), \(snapshot.formattedTemperature(imperial: imperial))"
    }
}

/// The stage's own words before the walk, and again from the walk's overflow
/// as "the day". The copy is the dataset's, unedited.
struct StageMorningCard: View {

    let stage: WayStage
    let weather: WeatherSnapshot?
    /// "walk" before the walk; "close" once it has begun.
    let buttonTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                    Text(stage.theme)
                        .font(Constants.Typography.displayMedium)
                        .foregroundColor(.ink)
                    Text(stage.narrative)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text(StageMorningCardModel.factsLine(for: stage))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                    warnings
                    if let weatherLine = StageMorningCardModel.weatherLine(weather) {
                        Text(weatherLine)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Constants.UI.Padding.normal)
            }
            Button(action: onAction) {
                Text(buttonTitle)
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone)
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .padding(Constants.UI.Padding.normal)
        }
        .background(Color.parchment)
    }

    /// Each warning its own short paragraph: two crowded onto one line is
    /// how a warning stops being read.
    @ViewBuilder
    private var warnings: some View {
        if !stage.warnings.isEmpty {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                ForEach(Array(stage.warnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: Constants.UI.Padding.small) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.rust)
                        Text(warning)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.ink)
                    }
                }
            }
        }
    }
}
