import SwiftUI

/// Modal picker for choosing a soundscape during meditation. Extracted
/// from MeditationView so the main file stays within SwiftLint's
/// file_length limit. Reads live state from `SoundscapePlayer.shared`
/// via @ObservedObject so the current selection's checkmark updates
/// live as the player's state changes.
struct SoundscapePickerSheet: View {

    @Binding var isPresented: Bool
    @ObservedObject private var soundscapePlayer = SoundscapePlayer.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Soundscape")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(AudioManifestService.shared.soundscapes) { scape in
                        soundscapeRow(scape)
                    }
                    noneRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, Constants.UI.Padding.big)
            }
        }
    }

    private func soundscapeRow(_ scape: AudioAsset) -> some View {
        let isSelected = soundscapePlayer.currentAsset?.id == scape.id
            || (soundscapePlayer.currentAsset == nil && UserPreferences.selectedSoundscapeId.value == scape.id)
        return Button {
            UserPreferences.selectedSoundscapeId.value = scape.id
            if AudioFileStore.shared.isAvailable(scape) {
                soundscapePlayer.play(scape, volume: Float(UserPreferences.soundscapeVolume.value))
            }
            isPresented = false
        } label: {
            pickerRowLabel(
                title: scape.displayName,
                titleOpacity: 0.9,
                isSelected: isSelected
            )
        }
    }

    private var noneRow: some View {
        Button {
            soundscapePlayer.stop()
            UserPreferences.selectedSoundscapeId.value = nil
            isPresented = false
        } label: {
            let noneSelected = soundscapePlayer.currentAsset == nil
                && UserPreferences.selectedSoundscapeId.value == nil
            pickerRowLabel(
                title: "None",
                titleOpacity: 0.5,
                isSelected: noneSelected
            )
        }
    }

    private func pickerRowLabel(title: String, titleOpacity: Double, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .font(Constants.Typography.body)
                .foregroundColor(Color.ink.opacity(titleOpacity))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.moss)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isSelected ? Color.moss.opacity(0.08) : Color.clear)
        .cornerRadius(10)
    }
}
