import SwiftUI

struct WhisperPlacementSheet: View {

    let currentLocation: TempRouteDataSample?
    let onPlace: (WhisperDefinition, KanjiExpiryPicker.ExpiryDuration) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var whisperPlayer = WhisperPlayer.shared
    @ObservedObject private var manifestService = WhisperManifestService.shared
    @State private var selectedCategory: WhisperCategory?
    @State private var selectedExpiry: KanjiExpiryPicker.ExpiryDuration = .sevenDays
    @State private var previewingCategory: WhisperCategory?

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
                    Text("Choose an energy")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(manifestService.placeableCategories(), id: \.rawValue) { category in
                                categoryRow(category)
                            }
                        }
                    }
                }

                privacyNotice

                Button(action: {
                    guard let category = selectedCategory else { return }
                    let whispers = manifestService.placeableWhispers(for: category)
                    guard let whisper = whispers.randomElement() else { return }
                    whisperPlayer.stop()
                    onPlace(whisper, selectedExpiry)
                }) {
                    Text("Leave Whisper")
                        .font(Constants.Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedCategory != nil ? Color.stone : Color.fog.opacity(0.3))
                        .foregroundColor(selectedCategory != nil ? .parchment : .fog)
                        .cornerRadius(Constants.UI.CornerRadius.normal)
                }
                .disabled(selectedCategory == nil)
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.big)

            Spacer()
        }
        .onDisappear {
            whisperPlayer.stop()
        }
        .onChange(of: selectedCategory) { newValue in
            guard let newValue else { return }
            whisperPlayer.prefetchCategory(newValue)
        }
    }

    private func categoryRow(_ category: WhisperCategory) -> some View {
        let isSelected = selectedCategory == category
        let isPreviewing = whisperPlayer.isPlaying && previewingCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 12) {
                Button {
                    if isPreviewing {
                        whisperPlayer.stop()
                        previewingCategory = nil
                    } else {
                        let whispers = manifestService.whispers(for: category)
                        if let whisper = whispers.randomElement() {
                            whisperPlayer.preview(whisper)
                            previewingCategory = category
                            selectedCategory = category
                        }
                    }
                } label: {
                    Image(systemName: isPreviewing ? "stop.circle" : "play.circle")
                        .font(.title3)
                        .foregroundColor(Color(category.borderColor))
                }

                Text(category.rawValue.capitalized)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink.opacity(0.9))

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
                    .stroke(Color(category.borderColor), lineWidth: isSelected ? 2 : 1)
                    .opacity(isSelected ? 1.0 : 0.4)
            )
        }
    }

    private var privacyNotice: some View {
        Text("Your location is shared anonymously. Whispers expire after the chosen duration. A random message from this category will be placed.")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
