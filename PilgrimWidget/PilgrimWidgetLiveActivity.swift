import ActivityKit
import WidgetKit
import SwiftUI

struct PilgrimWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(formatDistance(context.state.distanceMeters, imperial: context.attributes.isImperial),
                          systemImage: "figure.walk")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatDuration(context.state.activeDurationSeconds))
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    if let intention = context.attributes.intention {
                        Text(intention)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if context.state.isMeditating {
                            Label("Meditating", systemImage: "circle.circle")
                                .font(.caption2)
                        }
                        if context.state.isRecordingVoice {
                            Label("Recording", systemImage: "mic.fill")
                                .font(.caption2)
                        }
                        if context.state.isPaused {
                            Label("Paused", systemImage: "pause.fill")
                                .font(.caption2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isMeditating ? "circle.circle" : "figure.walk")
                    .foregroundColor(.green)
            } compactTrailing: {
                Text(formatDistance(context.state.distanceMeters, imperial: context.attributes.isImperial))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "figure.walk")
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WalkActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDuration(context.state.activeDurationSeconds))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundColor(.primary)
                Text("Duration")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDistance(context.state.distanceMeters, imperial: context.attributes.isImperial))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundColor(.primary)
                Text("Distance")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if context.state.isMeditating || context.state.isRecordingVoice || context.state.isPaused {
                stateIndicator(context.state)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func stateIndicator(_ state: WalkActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Image(systemName: "pause.fill")
                .foregroundColor(.orange)
        } else if state.isMeditating {
            Image(systemName: "circle.circle")
                .foregroundColor(.green)
        } else if state.isRecordingVoice {
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatDistance(_ meters: Double, imperial: Bool) -> String {
        if imperial {
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
        let km = meters / 1000
        return String(format: "%.2f km", km)
    }
}

#Preview("Notification", as: .content, using: WalkActivityAttributes(
    walkStartDate: Date().addingTimeInterval(-3600),
    intention: "Walk slowly today",
    isImperial: false
)) {
    PilgrimWidgetLiveActivity()
} contentStates: {
    WalkActivityAttributes.ContentState(
        activeDurationSeconds: 3661,
        distanceMeters: 4200,
        isPaused: false,
        isMeditating: false,
        isRecordingVoice: false
    )
    WalkActivityAttributes.ContentState(
        activeDurationSeconds: 1200,
        distanceMeters: 1500,
        isPaused: false,
        isMeditating: true,
        isRecordingVoice: false
    )
}
