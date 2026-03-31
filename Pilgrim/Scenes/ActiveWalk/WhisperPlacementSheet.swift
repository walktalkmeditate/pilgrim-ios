import SwiftUI

struct WhisperPlacementSheet: View {

    let currentLocation: TempRouteDataSample?
    let onPlace: (WhisperDefinition, KanjiExpiryPicker.ExpiryDuration) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var whisperPlayer = WhisperPlayer.shared
    @State private var selectedWhisper: WhisperDefinition?
    @State private var selectedExpiry: KanjiExpiryPicker.ExpiryDuration = .sevenDays

    var body: some View {
        VStack(spacing: 0) {
            Text("Leave a Whisper")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                    Text("Duration")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))

                    KanjiExpiryPicker(selected: $selectedExpiry)
                }

                VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                    Text("Choose a whisper")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(WhisperCatalog.all) { whisper in
                                whisperRow(whisper)
                            }
                        }
                    }
                }

                privacyNotice

                Button(action: {
                    guard let whisper = selectedWhisper else { return }
                    whisperPlayer.stop()
                    onPlace(whisper, selectedExpiry)
                }) {
                    Text("Leave Whisper")
                        .font(Constants.Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedWhisper != nil ? Color.stone : Color.fog.opacity(0.3))
                        .foregroundColor(selectedWhisper != nil ? .parchment : .fog)
                        .cornerRadius(Constants.UI.CornerRadius.normal)
                }
                .disabled(selectedWhisper == nil)
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.big)

            Spacer()
        }
        .onDisappear {
            whisperPlayer.stop()
        }
    }

    private func whisperRow(_ whisper: WhisperDefinition) -> some View {
        let isSelected = selectedWhisper?.id == whisper.id
        return Button {
            selectedWhisper = whisper
        } label: {
            HStack(spacing: 12) {
                Button {
                    if whisperPlayer.isPlaying, selectedWhisper?.id == whisper.id {
                        whisperPlayer.stop()
                    } else {
                        whisperPlayer.preview(whisper)
                        selectedWhisper = whisper
                    }
                } label: {
                    Image(systemName: whisperPlayer.isPlaying && selectedWhisper?.id == whisper.id
                          ? "stop.circle" : "play.circle")
                        .font(.title3)
                        .foregroundColor(.stone)
                }

                Text(whisper.title)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.stone)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
                    .fill(isSelected ? Color.parchmentSecondary.opacity(0.5) : Color.parchmentSecondary.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
                    .stroke(Color(whisper.category.borderColor), lineWidth: isSelected ? 2 : 1)
                    .opacity(isSelected ? 1.0 : 0.4)
            )
        }
    }

    private var privacyNotice: some View {
        Text("Your location is shared anonymously. Whispers expire after the chosen duration.")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
