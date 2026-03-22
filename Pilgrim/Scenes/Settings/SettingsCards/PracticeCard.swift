import SwiftUI

struct PracticeCard: View {

    @State private var beginWithIntention = UserPreferences.beginWithIntention.value
    @State private var celestialAwareness = UserPreferences.celestialAwarenessEnabled.value
    @State private var zodiacSystem = UserPreferences.zodiacSystem.value
    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers
    @State private var contributeToCollective = UserPreferences.contributeToCollective.value

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Practice", subtitle: "How you walk")

            settingToggle(
                label: "Begin with intention",
                description: "Set an intention before each walk",
                isOn: $beginWithIntention
            ) { newValue in
                UserPreferences.beginWithIntention.value = newValue
            }

            settingToggle(
                label: "Celestial awareness",
                description: "Moon phases, planetary hours, and zodiac during walks",
                isOn: $celestialAwareness
            ) { newValue in
                UserPreferences.celestialAwarenessEnabled.value = newValue
            }

            if celestialAwareness {
                settingPicker(
                    label: "Zodiac system",
                    selection: $zodiacSystem,
                    options: [("Tropical", "tropical"), ("Sidereal", "sidereal")]
                ) { newValue in
                    UserPreferences.zodiacSystem.value = newValue
                }
            }

            Divider()

            settingPicker(
                label: "Units",
                selection: $isMetric,
                options: [("Metric", true), ("Imperial", false)]
            ) { metric in
                UserPreferences.applyUnitSystem(metric: metric)
            }

            Text(isMetric ? "km \u{00B7} min/km \u{00B7} m \u{00B7} \u{00B0}C" : "mi \u{00B7} min/mi \u{00B7} ft \u{00B7} \u{00B0}F")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)

            Divider()

            settingToggle(
                label: "Walk with the collective",
                description: "Add your footsteps to the path",
                isOn: $contributeToCollective
            ) { newValue in
                UserPreferences.contributeToCollective.value = newValue
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: celestialAwareness)
    }
}
