import SwiftUI

struct WalkOptionsSheet: View {

    let isRecording: Bool
    var onSetIntention: (() -> Void)?
    var onDropWaypoint: (() -> Void)?
    let currentIntention: String?
    let waypointCount: Int

    var soundscapeName: String?
    var isSoundscapeMuted: Bool = false
    var onToggleSoundscape: (() -> Void)?

    var voiceGuidePackName: String?
    var isVoiceGuidePaused: Bool = false
    var hasLastPrompt: Bool = false
    var onToggleVoiceGuide: (() -> Void)?
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
                    audioSection
                }
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.big)

            Spacer()
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        let hasSoundscape = soundscapeName != nil || isSoundscapeMuted
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
                        icon: isSoundscapeMuted ? "speaker.slash" : "speaker.wave.2",
                        title: "Soundscape",
                        subtitle: isSoundscapeMuted ? "Paused" : soundscapeName
                    ) {
                        onToggleSoundscape?()
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
