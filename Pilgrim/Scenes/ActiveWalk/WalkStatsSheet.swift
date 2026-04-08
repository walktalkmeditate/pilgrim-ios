import SwiftUI

/// Collapsible state of the stats sheet during an active walk.
/// Owned by `ActiveWalkView`, bound into `WalkStatsSheet`.
enum SheetState {
    case minimized  // Thin bar: drag handle + timer + distance
    case expanded   // Full stats + controls
}

/// Collapsible stats sheet for the active walk screen.
///
/// Two visual states driven by `@Binding var state: SheetState`:
/// - `.minimized` (during a recording walk): thin bar with drag handle + timer + distance
/// - `.expanded` (pre-walk, paused, or user-expanded): full stats + controls
///
/// The minimized state only applies while the walk is actively recording.
/// Pre-walk (`.waiting` / `.ready`) always shows the expanded content so the
/// Start button is visible. Paused/autoPaused auto-expands so context is clear.
struct WalkStatsSheet: View {

    @Binding var state: SheetState
    @ObservedObject var viewModel: ActiveWalkViewModel
    let onStartMeditation: () -> Void
    let onRequestEndWalk: () -> Void

    @State private var dragOffset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distance (in points) the user must drag before a state change fires.
    private static let dragThreshold: CGFloat = 40

    /// Maximum visible drag offset — drag beyond this point resists further movement.
    private static let dragClamp: CGFloat = 100

    /// Velocity threshold for a "flick" gesture. If the user releases a drag
    /// moving faster than this, state changes even if distance is below threshold.
    private static let flickVelocity: CGFloat = 300

    private var isLargeText: Bool {
        dynamicTypeSize >= .accessibility2
    }

    /// True only when the walk is actively recording AND the state is minimized.
    /// Pre-walk, paused, and autoPaused states always render expanded content.
    /// We check `.recording` explicitly because `isActiveStatus` would include
    /// `.paused` and `.autoPaused` — we want the sheet expanded in those states.
    private var showsMinimized: Bool {
        state == .minimized && viewModel.status == .recording
    }

    /// Drag gesture is only meaningful during an active recording walk.
    /// In pre-walk and paused states, the sheet is locked in its current state.
    private var canDrag: Bool {
        viewModel.status == .recording
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            if showsMinimized {
                minimizedContent
                    .transition(.opacity)
            } else {
                expandedContent
                    .transition(.opacity)
            }
        }
        .offset(y: dragOffset)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: showsMinimized)
        .simultaneousGesture(dragGesture)
        .onChange(of: showsMinimized) { _, _ in
            // Reset any lingering drag offset when the state changes
            // (e.g., due to status flip mid-drag). Keeps layout clean.
            dragOffset = 0
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard canDrag else { return }
                let translation = value.translation.height

                if showsMinimized && translation < 0 {
                    // Dragging up from minimized — reveal expanded content
                    dragOffset = max(translation, -Self.dragClamp)
                } else if !showsMinimized && translation > 0 {
                    // Dragging down from expanded — preview minimized
                    dragOffset = min(translation, Self.dragClamp)
                }
            }
            .onEnded { value in
                guard canDrag else {
                    animateDragOffsetToZero()
                    return
                }

                let translation = value.translation.height
                // Predicted end translation extrapolates the gesture's motion
                // into the future assuming deceleration. The delta from the
                // current translation is a reasonable proxy for velocity.
                let predictedDelta = value.predictedEndTranslation.height - translation

                // Trigger state change if user crossed the distance threshold
                // OR flicked hard enough (predicted end travel).
                let shouldExpand = showsMinimized &&
                    (translation < -Self.dragThreshold || predictedDelta < -Self.flickVelocity)
                let shouldCollapse = !showsMinimized &&
                    (translation > Self.dragThreshold || predictedDelta > Self.flickVelocity)

                if shouldExpand {
                    // Reset offset instantly so only the state spring animates.
                    // onChange(of: showsMinimized) also clears any residual offset.
                    dragOffset = 0
                    fireHaptic()
                    state = .expanded
                } else if shouldCollapse {
                    dragOffset = 0
                    fireHaptic()
                    state = .minimized
                } else {
                    // Didn't cross threshold — rubber-band back to 0
                    animateDragOffsetToZero()
                }
            }
    }

    /// Rubber-bands the drag offset back to zero with a spring. Respects
    /// reduce motion — instant snap if the user has it enabled.
    private func animateDragOffsetToZero() {
        if reduceMotion {
            dragOffset = 0
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                dragOffset = 0
            }
        }
    }

    /// Fires a soft impact haptic for sheet state transitions.
    /// Creates a fresh generator per call — SwiftUI structs re-create on
    /// every body eval (many times per second during an active walk), so
    /// a stored generator would leak references per CLAUDE.md. Cold-start
    /// latency is ~10ms which is imperceptible for a tap-response.
    private func fireHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.fog.opacity(0.35))
            .frame(width: 40, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    // MARK: - Minimized

    /// Thin bar with timer and distance only. Tappable as a quick alternative
    /// to the drag gesture — tap expands the sheet. Uses a plain tap gesture
    /// (not a Button wrapper) so the drag gesture can coexist cleanly.
    private var minimizedContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.UI.Padding.big) {
            Text(viewModel.duration)
                .font(Constants.Typography.timer)
                .foregroundColor(.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.distance)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Distance")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.6))
            }
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.top, Constants.UI.Padding.small)
        .padding(.bottom, Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            state = .expanded
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk stats")
        .accessibilityValue("\(viewModel.duration), \(viewModel.distance)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to show full stats and controls")
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            statsSection
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
