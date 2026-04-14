import SwiftUI

struct PracticeCard: View {

    @State private var beginWithIntention = UserPreferences.beginWithIntention.value
    @State private var celestialAwareness = UserPreferences.celestialAwarenessEnabled.value
    @State private var zodiacSystem = UserPreferences.zodiacSystem.value
    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers
    @State private var contributeToCollective = UserPreferences.contributeToCollective.value
    @State private var autoPlayWhisper = UserPreferences.autoPlayWhisperOnProximity.value
    @State private var walkReliquary = UserPreferences.walkReliquaryEnabled.value
    @State private var showPhotosDeniedNote = false

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
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Divider()

            settingToggle(
                label: "Walk with the collective",
                description: "Add your footsteps to the path",
                isOn: $contributeToCollective
            ) { newValue in
                UserPreferences.contributeToCollective.value = newValue
            }

            settingToggle(
                label: "Auto-play nearby whispers",
                description: "Hear whispers left by other pilgrims as you walk near them",
                isOn: $autoPlayWhisper
            ) { newValue in
                UserPreferences.autoPlayWhisperOnProximity.value = newValue
            }

            settingToggle(
                label: "Gather walk photos",
                description: "Find photos you took along each walk and pin them to the route. Photos stay in Apple Photos — never copied or uploaded.",
                isOn: $walkReliquary
            ) { newValue in
                if newValue {
                    // Clear any lingering denial note for this attempt.
                    showPhotosDeniedNote = false
                    PermissionManager.standard.checkPhotosPermission { granted in
                        // Guard against a stale callback: if the user has since toggled off,
                        // don't resurrect the ON state.
                        guard walkReliquary else {
                            UserPreferences.walkReliquaryEnabled.value = false
                            return
                        }
                        if granted {
                            UserPreferences.walkReliquaryEnabled.value = true
                        } else {
                            walkReliquary = false
                            UserPreferences.walkReliquaryEnabled.value = false
                            showPhotosDeniedNote = true
                        }
                    }
                } else {
                    // The denial path above also programmatically flips `walkReliquary` to
                    // false, re-entering this branch. Persist the OFF state but do NOT clear
                    // `showPhotosDeniedNote` — letting the note survive the revert is the
                    // whole point of showing it. The note naturally clears on the next
                    // successful ON attempt (where this branch is skipped entirely).
                    UserPreferences.walkReliquaryEnabled.value = false
                }
            }

            if showPhotosDeniedNote {
                Text("Photo access was declined. To enable the reliquary, grant Photo Library access in iOS Settings → Pilgrim.")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .padding(.top, 4)
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: celestialAwareness)
        .animation(.easeInOut(duration: 0.2), value: showPhotosDeniedNote)
    }
}
