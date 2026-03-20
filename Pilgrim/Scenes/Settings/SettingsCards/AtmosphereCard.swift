import SwiftUI

struct AtmosphereCard: View {

    @State private var appearanceMode = UserPreferences.appearanceMode.value
    @State private var soundsEnabled = UserPreferences.soundsEnabled.value

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Atmosphere", subtitle: "Look and feel")

            settingPicker(
                label: "Appearance",
                selection: $appearanceMode,
                options: [("Auto", "system"), ("Light", "light"), ("Dark", "dark")]
            ) { newValue in
                UserPreferences.appearanceMode.value = newValue
            }

            Divider()

            settingToggle(
                label: "Sounds",
                description: "Bells, haptics, and ambient soundscapes",
                isOn: $soundsEnabled
            ) { newValue in
                UserPreferences.soundsEnabled.value = newValue
            }

            if soundsEnabled {
                NavigationLink {
                    SoundSettingsView()
                } label: {
                    settingNavRow(label: "Bells & Soundscapes")
                }
            }
        }
        .settingsCard()
        .animation(.easeInOut(duration: 0.2), value: soundsEnabled)
    }
}
