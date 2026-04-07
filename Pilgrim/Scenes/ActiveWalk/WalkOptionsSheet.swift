import SwiftUI
import Network

struct WalkOptionsSheet: View {

    let isRecording: Bool
    var onSetIntention: (() -> Void)?
    var onDropWaypoint: (() -> Void)?
    let currentIntention: String?
    let waypointCount: Int

    var canPlaceWhisper: Bool = false
    var isWhisperUnlocked: Bool = false
    var whispersRemaining: Int = 7
    var onLeaveWhisper: (() -> Void)?

    var canPlaceStone: Bool = false
    var isStoneUnlocked: Bool = false
    var onPlaceStone: (() -> Void)?

    var soundscapeName: String?
    var isSoundscapePlaying: Bool = false
    var onToggleSoundscape: (() -> Void)?
    var onSelectSoundscape: ((String) -> Void)?

    var voiceGuidePackName: String?
    var isVoiceGuidePaused: Bool = false
    var hasLastPrompt: Bool = false
    var onToggleVoiceGuide: (() -> Void)?
    var onSelectVoiceGuide: ((String) -> Void)?
    var onReplayPrompt: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Text("Options")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            VStack(spacing: 6) {
                if !isRecording, let onSetIntention {
                    optionRow(
                        icon: "leaf",
                        title: "Set Intention",
                        subtitle: currentIntention
                    ) {
                        onSetIntention()
                    }
                }

                if isRecording, let onDropWaypoint {
                    optionRow(
                        icon: "mappin",
                        title: "Drop Waypoint",
                        subtitle: waypointCount > 0 ? "\(waypointCount) marked" : nil
                    ) {
                        onDropWaypoint()
                    }
                }

                if isRecording {
                    traceSection
                    audioSection
                }
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.big)

            Spacer()
        }
        .onAppear { checkConnectivity() }
    }

    @State private var isConnected = false

    private func checkConnectivity() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
            }
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue(label: "connectivity-check"))
    }

    @ViewBuilder
    private var traceSection: some View {
        if !isConnected { EmptyView() }
        else {
        VStack(alignment: .leading, spacing: 4) {
            Text("Traces")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.5))
                .padding(.top, 8)
                .padding(.leading, 4)

            optionRow(
                icon: "wind",
                title: "Leave a Whisper",
                subtitle: isWhisperUnlocked
                    ? "\(whispersRemaining) remaining"
                    : "Unlocks at 7 min"
            ) {
                onLeaveWhisper?()
            }
            .disabled(!canPlaceWhisper)
            .opacity(canPlaceWhisper ? 1.0 : 0.4)

            optionRow(
                icon: "mountain.2",
                title: "Place a Stone",
                subtitle: isStoneUnlocked
                    ? (canPlaceStone ? "1 remaining" : "Placed")
                    : "Unlocks at 12 min"
            ) {
                onPlaceStone?()
            }
            .disabled(!canPlaceStone)
            .opacity(canPlaceStone ? 1.0 : 0.4)
        }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        let hasSoundscape = soundscapeName != nil
        let hasVoiceGuide = voiceGuidePackName != nil

        if hasSoundscape || hasVoiceGuide {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.5))
                    .padding(.top, 8)
                    .padding(.leading, 4)

                if hasSoundscape {
                    optionRow(
                        icon: isSoundscapePlaying ? "speaker.wave.2" : "speaker.slash",
                        title: "Soundscape",
                        subtitle: isSoundscapePlaying ? soundscapeName : "Off"
                    ) {
                        onToggleSoundscape?()
                    }
                    .contextMenu {
                        ForEach(AudioManifestService.shared.soundscapes) { scape in
                            Button {
                                onSelectSoundscape?(scape.id)
                            } label: {
                                Label(scape.displayName, systemImage:
                                    UserPreferences.selectedSoundscapeId.value == scape.id
                                    ? "checkmark" : "speaker.wave.2")
                            }
                        }
                    }
                }

                if hasVoiceGuide {
                    optionRow(
                        icon: isVoiceGuidePaused ? "play.circle" : "pause.circle",
                        title: "Voice Guide",
                        subtitle: isVoiceGuidePaused ? "Paused — \(voiceGuidePackName ?? "")" : voiceGuidePackName
                    ) {
                        onToggleVoiceGuide?()
                    }
                    .contextMenu {
                        let downloadedPacks = VoiceGuideManifestService.shared.packs
                            .filter { VoiceGuideFileStore.shared.isPackDownloaded($0) }
                        if downloadedPacks.count > 1 {
                            ForEach(downloadedPacks) { pack in
                                Button {
                                    onSelectVoiceGuide?(pack.id)
                                } label: {
                                    Label(pack.name, systemImage:
                                        UserPreferences.selectedVoiceGuidePackId.value == pack.id
                                        ? "checkmark" : pack.iconName)
                                }
                            }
                        }
                    }

                    if hasLastPrompt {
                        optionRow(
                            icon: "arrow.counterclockwise",
                            title: "Replay Last Prompt",
                            subtitle: nil
                        ) {
                            onReplayPrompt?()
                        }
                    }
                }
            }
        }
    }

    private func optionRow(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(.moss)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink.opacity(0.9))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.fog.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                    .fill(Color.parchmentSecondary.opacity(0.3))
            )
        }
    }
}
