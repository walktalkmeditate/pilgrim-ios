import SwiftUI
import Combine

struct AtmosphereCard: View {

    @State private var appearanceMode = UserPreferences.appearanceMode.value
    @State private var soundsEnabled = UserPreferences.soundsEnabled.value
    @State private var modeCancellable: AnyCancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Atmosphere", subtitle: "Look and feel")

            NavigationLink(destination: AppearanceView()) {
                HStack {
                    Text("Appearance")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: glyph(for: appearanceMode))
                            .font(.body)
                            .foregroundColor(.fog)
                        Text(label(for: appearanceMode))
                            .font(Constants.Typography.body)
                            .foregroundColor(.fog)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.fog)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .onAppear {
            soundsEnabled = UserPreferences.soundsEnabled.value
            appearanceMode = UserPreferences.appearanceMode.value
            modeCancellable = UserPreferences.appearanceMode.publisher
                .receive(on: DispatchQueue.main)
                .sink { newValue in
                    appearanceMode = newValue
                }
        }
        .onDisappear {
            modeCancellable?.cancel()
            modeCancellable = nil
        }
    }

    private func glyph(for mode: String) -> String {
        switch mode {
        case "light":         return "sun.max"
        case "dark":          return "moon"
        case "constellation": return "sparkles"
        default:              return "circle.righthalf.filled"
        }
    }

    private func label(for mode: String) -> String {
        switch mode {
        case "light":         return "Light"
        case "dark":          return "Dark"
        case "constellation": return "Constellation"
        default:              return "Auto"
        }
    }
}
