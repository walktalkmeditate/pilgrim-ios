import SwiftUI

struct VoiceRecordingRow: View {
    let index: Int
    let recording: VoiceRecordingInterface
    let transcription: String?
    let fileAvailable: Bool
    let isActive: Bool
    let isPlaying: Bool
    let progress: Double
    let currentTime: TimeInterval
    let audioDuration: TimeInterval
    let playbackSpeed: Float
    let onTogglePlay: () -> Void
    let onSeek: (Double) -> Void
    let onCycleSpeed: () -> Void
    let onRetranscribe: () -> Void
    let onDelete: () -> Void
    let onTranscriptionSave: ((String) -> Void)?
    let waveformSamples: [Float]?

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isEditFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if fileAvailable {
                HStack(spacing: Constants.UI.Padding.small) {
                    Button(action: onTogglePlay) {
                        Image(systemName: isActive && isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.stone)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recording \(index)")
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        HStack(spacing: Constants.UI.Padding.xs) {
                            Text(formattedDuration)
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                            if recording.isEnhanced {
                                Text("·")
                                    .foregroundColor(.fog)
                                Text("Enhanced")
                                    .font(Constants.Typography.caption)
                                    .foregroundColor(.stone)
                            }
                        }
                    }
                    Spacer()
                    Text(formattedTime)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                    Button(action: onCycleSpeed) {
                        Text(speedLabel)
                            .font(Constants.Typography.caption)
                            .foregroundColor(playbackSpeed > 1.0 ? .parchment : .stone)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(playbackSpeed > 1.0 ? Color.stone : Color.stone.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                if let samples = waveformSamples {
                    WaveformBarView(
                        samples: samples,
                        progress: isActive ? progress : 0,
                        isPlaying: isPlaying
                    ) { fraction in
                        if isActive {
                            onSeek(fraction)
                        } else {
                            onTogglePlay()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onSeek(fraction)
                            }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.fog.opacity(0.15))
                        .frame(height: 28)
                }

                if isActive {
                    HStack {
                        Text(formatSeconds(currentTime))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                            .monospacedDigit()
                        Spacer()
                        Text(formatSeconds(audioDuration))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                            .monospacedDigit()
                    }
                }
            } else {
                HStack {
                    Image(systemName: "waveform.slash")
                        .font(.title2)
                        .foregroundColor(.fog)
                    Text("Recording unavailable")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog)
                    Spacer()
                }
            }

            if let transcription = transcription {
                HStack(alignment: .top) {
                    if isEditing {
                        VStack(alignment: .trailing, spacing: 4) {
                            TextEditor(text: $editText)
                                .font(Constants.Typography.body)
                                .foregroundColor(.ink)
                                .focused($isEditFocused)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 60, maxHeight: 200)
                                .padding(4)
                                .background(Color.parchmentTertiary)
                                .cornerRadius(8)
                            Button {
                                let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    onTranscriptionSave?(trimmed)
                                }
                                isEditing = false
                                isEditFocused = false
                            } label: {
                                Text("Done")
                                    .font(Constants.Typography.caption)
                                    .foregroundColor(.stone)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.stone.opacity(0.12))
                                    .cornerRadius(4)
                            }
                        }
                    } else {
                        Text(transcription)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.parchmentTertiary)
                            .cornerRadius(8)
                            .onTapGesture {
                                editText = transcription
                                isEditing = true
                                isEditFocused = true
                            }
                    }

                    if fileAvailable && !isEditing {
                        Button(action: onRetranscribe) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.fog)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if fileAvailable {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Recording File", systemImage: "trash")
                }
            }
        }
    }

    private var speedLabel: String {
        playbackSpeed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fx", playbackSpeed)
            : String(format: "%gx", playbackSpeed)
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var formattedDuration: String {
        formatSeconds(recording.duration)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var formattedTime: String {
        Self.timeFormatter.string(from: recording.startDate)
    }
}
