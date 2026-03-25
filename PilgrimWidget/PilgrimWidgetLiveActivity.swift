import ActivityKit
import WidgetKit
import SwiftUI

struct PilgrimWidgetLiveActivity: Widget {

    private static let parchment = Color(red: 0.110, green: 0.098, blue: 0.078)
    private static let ink = Color(red: 0.941, green: 0.922, blue: 0.882)
    private static let fog = Color(red: 0.420, green: 0.388, blue: 0.349)
    private static let moss = Color(red: 0.584, green: 0.659, blue: 0.533)
    private static let rust = Color(red: 0.769, green: 0.494, blue: 0.388)
    private static let stone = Color(red: 0.722, green: 0.592, blue: 0.431)

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
                    if let start = context.state.walkTimerStart {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(formatDuration(context.state.activeDurationSeconds))
                            .font(.caption.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let intention = context.attributes.intention {
                        Text(intention)
                            .font(.system(.caption2, design: .serif))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottomBar(context.state)
                }
            } compactLeading: {
                compactLeadingView(context.state)
            } compactTrailing: {
                compactTrailingView(context.state, imperial: context.attributes.isImperial)
            } minimal: {
                Image(systemName: "figure.walk")
            }
        }
    }

    // MARK: - Compact Dynamic Island

    @ViewBuilder
    private func compactLeadingView(_ state: WalkActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Image(systemName: "pause.fill")
                .foregroundColor(.orange)
        } else if state.isMeditating {
            Image(systemName: "circle.circle")
                .foregroundColor(Self.moss)
        } else if state.isRecordingVoice {
            Image(systemName: "mic.fill")
                .foregroundColor(Self.rust)
        } else {
            Image(systemName: "figure.walk")
                .foregroundColor(Self.stone)
        }
    }

    @ViewBuilder
    private func compactTrailingView(_ state: WalkActivityAttributes.ContentState, imperial: Bool) -> some View {
        if let start = state.meditationTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .font(.caption2.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
        } else if let start = state.talkTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .font(.caption2.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
        } else {
            Text(formatDistance(state.distanceMeters, imperial: imperial))
                .font(.caption2.monospacedDigit())
        }
    }

    // MARK: - Expanded Dynamic Island

    @ViewBuilder
    private func expandedBottomBar(_ state: WalkActivityAttributes.ContentState) -> some View {
        HStack(spacing: 16) {
            if let start = state.meditationTimerStart {
                HStack(spacing: 4) {
                    Image(systemName: "circle.circle")
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .multilineTextAlignment(.leading)
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(Self.moss)
            }
            if let start = state.talkTimerStart {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .multilineTextAlignment(.leading)
                }
                .font(.caption2.monospacedDigit())
                .foregroundColor(Self.rust)
            }
            if state.isPaused {
                Label("Paused", systemImage: "pause.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WalkActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if let start = context.state.walkTimerStart {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(.system(.title2, design: .rounded).monospacedDigit())
                            .foregroundColor(Self.ink)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(formatDuration(context.state.activeDurationSeconds))
                            .font(.system(.title2, design: .rounded).monospacedDigit())
                            .foregroundColor(Self.ink)
                    }
                    Text("Duration")
                        .font(.system(.caption2, design: .serif))
                        .foregroundColor(Self.fog)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDistance(context.state.distanceMeters, imperial: context.attributes.isImperial))
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundColor(Self.ink)
                    Text("Distance")
                        .font(.system(.caption2, design: .serif))
                        .foregroundColor(Self.fog)
                }

                if context.state.isMeditating || context.state.isRecordingVoice || context.state.isPaused {
                    stateIndicator(context.state)
                }
            }

            if context.state.meditationTimerStart != nil || context.state.talkTimerStart != nil {
                activityTimerBar(context.state)
            }
        }
        .padding()
        .background(Self.parchment)
    }

    @ViewBuilder
    private func stateIndicator(_ state: WalkActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Image(systemName: "pause.fill")
                .foregroundColor(.orange)
        } else if state.isMeditating {
            Image(systemName: "circle.circle")
                .foregroundColor(Self.moss)
        } else if state.isRecordingVoice {
            Image(systemName: "mic.fill")
                .foregroundColor(Self.rust)
        }
    }

    @ViewBuilder
    private func activityTimerBar(_ state: WalkActivityAttributes.ContentState) -> some View {
        HStack(spacing: 0) {
            if let start = state.meditationTimerStart {
                HStack(spacing: 4) {
                    Image(systemName: "circle.circle")
                        .font(.caption2)
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.leading)
                }
                .foregroundColor(Self.moss)
            }
            if state.meditationTimerStart != nil && state.talkTimerStart != nil {
                Spacer()
            }
            if let start = state.talkTimerStart {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.leading)
                }
                .foregroundColor(Self.rust)
            }
        }
    }

    // MARK: - Formatting

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
        walkTimerStart: Date().addingTimeInterval(-3661),
        distanceMeters: 4200,
        meditationTimerStart: nil,
        talkTimerStart: nil,
        isPaused: false,
        isMeditating: false,
        isRecordingVoice: false
    )
    WalkActivityAttributes.ContentState(
        activeDurationSeconds: 1200,
        walkTimerStart: Date().addingTimeInterval(-1200),
        distanceMeters: 1500,
        meditationTimerStart: Date().addingTimeInterval(-480),
        talkTimerStart: nil,
        isPaused: false,
        isMeditating: true,
        isRecordingVoice: false
    )
    WalkActivityAttributes.ContentState(
        activeDurationSeconds: 1800,
        walkTimerStart: Date().addingTimeInterval(-1800),
        distanceMeters: 2100,
        meditationTimerStart: nil,
        talkTimerStart: Date().addingTimeInterval(-195),
        isPaused: false,
        isMeditating: false,
        isRecordingVoice: true
    )
}
