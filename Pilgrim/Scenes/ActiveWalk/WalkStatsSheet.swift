import SwiftUI

/// Collapsible stats sheet for the active walk screen.
///
/// Renders walk stats (timer, distance, etc.) and controls (start, meditate,
/// mic, end). Sits at the bottom of `ActiveWalkView` over the map.
///
/// Stage 1: pure extraction of `statsSection` + `controlsSection`. No visual
/// or behavioral change. Collapsible state/drag gesture comes in later stages.
struct WalkStatsSheet: View {

    @ObservedObject var viewModel: ActiveWalkViewModel
    let onStartMeditation: () -> Void
    let onRequestEndWalk: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLargeText: Bool {
        dynamicTypeSize >= .accessibility2
    }

    var body: some View {
        VStack(spacing: 0) {
            statsSection
            Spacer(minLength: 0)
            controlsSection
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.normal) {
            VStack(spacing: 4) {
                Text(viewModel.duration)
                    .font(Constants.Typography.timer)
                    .foregroundColor(.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(viewModel.intention ?? "every step is enough")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .animation(.easeInOut(duration: 0.5), value: viewModel.currentSoundscapeName)

            HStack(spacing: Constants.UI.Padding.big) {
                StatItem(label: "Distance", value: viewModel.distance)
                StatItem(label: "Steps", value: viewModel.steps)
                StatItem(label: "Ascent", value: viewModel.ascent)
            }
            .minimumScaleFactor(0.6)

            HStack(spacing: isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.big) {
                TimeMetricItem(label: "Walk", value: viewModel.walkTime, icon: "figure.walk",
                               isActive: !viewModel.isRecordingVoice && !viewModel.isMeditating)
                TimeMetricItem(label: "Talk", value: viewModel.talkTime, icon: "waveform",
                               isActive: viewModel.isRecordingVoice)
                TimeMetricItem(label: "Meditate", value: viewModel.meditateTime, icon: "brain.head.profile",
                               isActive: viewModel.isMeditating)
            }
            .minimumScaleFactor(0.5)
        }
        .padding(.vertical, isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.normal)
        .padding(.horizontal, Constants.UI.Padding.normal)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            switch viewModel.status {
            case .waiting:
                SwiftUI.ProgressView()
                    .tint(.stone)
                    .frame(maxWidth: .infinity)
            case .ready:
                actionButton("Start", systemImage: "play.fill", color: .moss, isFilled: true) {
                    viewModel.startRecording()
                }
            case .recording, .paused, .autoPaused:
                actionButton("Meditate", systemImage: "brain.head.profile", color: .dawn) {
                    onStartMeditation()
                }
                micButton
                actionButton("End", systemImage: "stop.fill", color: .fog) {
                    onRequestEndWalk()
                }
            }
        }
        .padding(Constants.UI.Padding.normal)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    private var micButton: some View {
        let isActive = viewModel.isRecordingVoice
        let size: CGFloat = isLargeText ? 80 : 72
        return Button(action: { viewModel.toggleVoiceRecording() }) {
            VStack(spacing: isLargeText ? 2 : 6) {
                if isActive {
                    AudioWaveformView(level: viewModel.audioLevel)
                        .frame(width: 36, height: 24)
                } else {
                    Image(systemName: "mic")
                        .font(isLargeText ? .body : .title2)
                        .frame(height: isLargeText ? 20 : 24)
                }
                Text(isActive ? "Stop" : "Record")
                    .font(Constants.Typography.caption)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(.rust)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color.rust.opacity(isActive ? 0.15 : 0.06))
            )
            .background(
                Circle()
                    .stroke(Color.rust, lineWidth: isActive ? 2.5 : 1.5)
            )
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    private func actionButton(_ title: String, systemImage: String, color: Color, isFilled: Bool = false, action: @escaping () -> Void) -> some View {
        let size: CGFloat = isLargeText ? 80 : 72
        return Button(action: action) {
            VStack(spacing: isLargeText ? 2 : 6) {
                Image(systemName: systemImage)
                    .font(isLargeText ? .body : .title2)
                    .frame(height: isLargeText ? 20 : 24)
                Text(title)
                    .font(Constants.Typography.caption)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.opacity(isFilled ? 0.12 : 0.06))
            )
            .background(
                Circle()
                    .stroke(color, lineWidth: 1.5)
            )
        }
    }
}
