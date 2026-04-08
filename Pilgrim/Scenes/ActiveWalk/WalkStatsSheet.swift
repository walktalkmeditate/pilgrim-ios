import SwiftUI

/// Collapsible state of the stats sheet during an active walk.
/// Owned by `ActiveWalkView`, bound into `WalkStatsSheet`.
enum SheetState {
    case minimized  // Thin bar: drag handle + timer + distance
    case expanded   // Full stats + controls
}

/// Preference key for reporting the measured height of the minimized sheet
/// content (drag handle + stat row + padding, not including safe area).
/// `ActiveWalkView` reads this value to position the ambient overlay
/// (weather chip, sparkline, audio indicators) exactly above the sheet top,
/// avoiding the fragility of hardcoded height estimates.
struct MinimizedSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Preference key for reporting the measured height of the expanded sheet
/// content (drag handle + stats section + controls section, not including
/// safe area). `ActiveWalkView` reads this value to set the Mapbox camera's
/// bottom inset so the user's location puck stays visible above the sheet
/// in the expanded state. Separate from `MinimizedSheetHeightKey` so the
/// two values don't clobber each other during sheet state transitions.
struct ExpandedSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 340
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
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
    /// Increment from the parent to trigger a one-time "wink" hint
    /// animation — drag handle brightens and the sheet nudges up
    /// briefly, teaching the swipe-to-expand affordance. Fires after
    /// auto-collapse on walk start.
    let peekHintTrigger: Int

    @State private var dragOffset: CGFloat = 0
    /// Transient opacity boost added to the drag handle during the
    /// peek hint animation. Decays back to 0 after the wink completes.
    @State private var handleOpacityBoost: Double = 0
    /// Generation counter for cancelling in-flight peek hints if state
    /// changes before the delayed animation fires (e.g., walk cancelled
    /// or user drags mid-hint).
    @State private var peekHintGeneration: Int = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distance (in points) the user must drag before a state change fires.
    private static let dragThreshold: CGFloat = 40

    /// Maximum visible drag offset — drag beyond this point resists further movement.
    private static let dragClamp: CGFloat = 100

    /// Velocity threshold for a "flick" gesture. If the user releases a drag
    /// moving faster than this, state changes even if distance is below threshold.
    private static let flickVelocity: CGFloat = 300

    /// Vertical space the drag handle occupies (pill + top padding +
    /// bottom padding). Added to the measured minimizedContent /
    /// expandedContent height so the total matches the sheet's visible
    /// chrome above the safe area. Must stay in sync with the
    /// `dragHandle` view below.
    static let dragHandleTotalHeight: CGFloat = 5 + 8 + 4  // handle + top + bottom padding

    private var isLargeText: Bool {
        dynamicTypeSize >= .accessibility2
    }

    /// True when the sheet should render minimized content.
    /// Derived SOLELY from `state` — the parent (`ActiveWalkView`) is the
    /// single source of truth for what state to be in, and its debounce
    /// logic already filters out GPS-flap status thrashing. If we also
    /// checked `viewModel.status == .recording` here, brief auto-pauses
    /// would visually expand the sheet before the parent's debounce had
    /// a chance to see if the pause was real, causing UI thrashing.
    private var showsMinimized: Bool {
        state == .minimized
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
                    .background(
                        // Measure the full minimized bar (drag handle +
                        // content) height and publish it via preference
                        // key so the parent can position the ambient
                        // overlay exactly above the sheet top. Only attaches
                        // while minimized — expanded state doesn't use
                        // this measurement.
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: MinimizedSheetHeightKey.self,
                                    value: geo.size.height + Self.dragHandleTotalHeight
                                )
                        }
                    )
            } else {
                expandedContent
                    .transition(.opacity)
                    .background(
                        // Measure the expanded sheet chrome (drag handle +
                        // stats + controls) and publish so the parent can
                        // pass an accurate bottom inset to Mapbox, keeping
                        // the user's location puck visible above the sheet.
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: ExpandedSheetHeightKey.self,
                                    value: geo.size.height + Self.dragHandleTotalHeight
                                )
                        }
                    )
            }
        }
        .offset(y: dragOffset)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: showsMinimized)
        .simultaneousGesture(dragGesture)
        .onChange(of: showsMinimized) { _, _ in
            // Reset any lingering drag offset when the state changes
            // (e.g., due to status flip mid-drag). Animated so it glides
            // back to 0 if the user's finger released during the flip.
            animateDragOffsetToZero()
        }
        .onChange(of: peekHintTrigger) { _, _ in
            performPeekHint()
        }
        // Cap dynamic type at .accessibility3 for this sheet only. The rest
        // of the app scales to .accessibility5, but a glance-and-act walk
        // screen needs stats that fit without clipping and controls that
        // stay reachable. Beyond ax3, the value/label column layout starts
        // to overflow the available vertical budget regardless of how
        // aggressive the scaling factors are.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard canDrag else { return }
                // Cancel any pending peek hint — the user is already
                // discovering the gesture on their own, so the scheduled
                // wink is redundant and would fight their drag if it
                // fired mid-gesture.
                peekHintGeneration += 1
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
                    // Animate offset and state together so the sheet smoothly
                    // grows upward from the user's drag position, instead of
                    // snapping back to 0 before expanding.
                    fireHaptic()
                    commitSheetStateChange(to: .expanded)
                } else if shouldCollapse {
                    fireHaptic()
                    commitSheetStateChange(to: .minimized)
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

    /// Commits a sheet state change triggered by a drag, coordinating the
    /// state transition and the drag-offset reset in a single animation so
    /// the sheet glides smoothly instead of snapping back before expanding.
    private func commitSheetStateChange(to newState: SheetState) {
        if reduceMotion {
            dragOffset = 0
            state = newState
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                dragOffset = 0
                state = newState
            }
        }
    }

    /// Fires a soft impact haptic for sheet state transitions.
    /// Creates a fresh generator per call — storing it as a struct property
    /// would needlessly retain a Core Haptics resource across the lifetime
    /// of the sheet, and SwiftUI structs re-create on every body eval so
    /// @State-stored generators don't really help anyway. Cold-start latency
    /// is ~10ms which is imperceptible for a tap-response.
    private func fireHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// One-time "wink" hint: the drag handle brightens and the sheet
    /// nudges up briefly, teaching the swipe-to-expand affordance.
    /// Scheduled 0.7s after the trigger so it fires *after* the
    /// auto-collapse spring has settled, not on top of it. Uses a
    /// generation counter so a second trigger (or state change) can
    /// cancel an in-flight hint. Respects reduce motion.
    private func performPeekHint() {
        guard !reduceMotion else { return }
        peekHintGeneration += 1
        let gen = peekHintGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard peekHintGeneration == gen else { return }
            // Only wink if we're still minimized and can actually drag —
            // otherwise the hint doesn't match reality (e.g., walk was
            // cancelled during the delay, or the user is already dragging).
            guard showsMinimized, canDrag else { return }
            // Rise and brighten.
            withAnimation(.easeOut(duration: 0.28)) {
                dragOffset = -6
                handleOpacityBoost = 0.35
            }
            // After the peak holds briefly, settle back to rest.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                guard peekHintGeneration == gen else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    dragOffset = 0
                    handleOpacityBoost = 0
                }
            }
        }
    }

    // MARK: - Drag Handle

    /// Visual affordance for the collapsible sheet. Dimmer in non-recording
    /// states where drag is disabled — signals "not currently interactive".
    /// Receives a transient opacity boost during the peek hint "wink" so
    /// the handle briefly pronounces itself right after walk start.
    private var dragHandle: some View {
        let baseOpacity = canDrag ? 0.35 : 0.12
        let effectiveOpacity = min(1.0, baseOpacity + handleOpacityBoost)
        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.fog.opacity(effectiveOpacity))
            .frame(width: 40, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .animation(.easeInOut(duration: 0.2), value: canDrag)
            .accessibilityHidden(true)
    }

    // MARK: - Minimized

    /// Thin bar with optional intention mantra + three glance stats
    /// (time, distance, steps). Tappable as a quick alternative to the
    /// drag gesture — tap expands the sheet. Uses a plain tap gesture
    /// (not a Button wrapper) so the drag gesture can coexist cleanly.
    ///
    /// Uses `statColumn` helpers (not a shared component with equal-width
    /// frames) because the three stat values have very different glyph
    /// widths. Forcing equal-width columns via frame(maxWidth: .infinity)
    /// combined with per-Text minimumScaleFactor causes SwiftUI to measure
    /// and render each column inconsistently, producing visibly different
    /// sizes across the row. Natural sizing + Spacers gives each Text its
    /// intrinsic size at the same font, so the three values are guaranteed
    /// to render at identical type size. The sheet's .accessibility3 cap
    /// ensures nothing overflows even at the largest supported text size.
    private var minimizedContent: some View {
        VStack(spacing: isLargeText ? 4 : 6) {
            if let intention = viewModel.intention, !intention.isEmpty {
                Text(intention)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline) {
                statColumn(value: viewModel.duration, label: "Time")
                Spacer(minLength: Constants.UI.Padding.normal)
                statColumn(value: viewModel.distance, label: "Distance")
                Spacer(minLength: Constants.UI.Padding.normal)
                statColumn(value: viewModel.steps, label: "Steps")
            }
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.top, Constants.UI.Padding.small)
        .padding(.bottom, Constants.UI.Padding.small)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            state = .expanded
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk stats")
        .accessibilityValue(minimizedAccessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to show full stats and controls")
    }

    /// Single stat column used by both the minimized bar and the expanded
    /// stats section. No frame constraint, no minimumScaleFactor — the
    /// parent sheet is capped at .accessibility3 so everything is
    /// guaranteed to fit without scaling tricks. Using scaling + equal
    /// columns at the same time causes SwiftUI to render each column at
    /// a different effective size, producing visible inconsistency.
    private func statColumn(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(Constants.Typography.statValue)
                .monospacedDigit()
                .foregroundColor(.ink)
                .lineLimit(1)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
                .lineLimit(1)
        }
    }

    /// VoiceOver value for the minimized bar. Prepends the intention so
    /// walkers are reminded of their mantra when they check the stats,
    /// then reads the three glance stats.
    private var minimizedAccessibilityValue: String {
        let stats = "\(viewModel.duration), \(viewModel.distance), \(viewModel.steps) steps"
        if let intention = viewModel.intention, !intention.isEmpty {
            return "\(intention). \(stats)"
        }
        return stats
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

            // Equal-width columns via frame(maxWidth: .infinity) so this
            // row aligns vertically with the TimeMetricItem row below
            // (which also uses equal columns). Spacing matches the
            // TimeMetricItem row exactly so each column's center lines
            // up between the two rows. No minimumScaleFactor because the
            // sheet is capped at .accessibility3 and the stat values
            // comfortably fit at that ceiling — scaling is the mechanism
            // that caused inconsistent per-column sizing.
            HStack(spacing: isLargeText ? Constants.UI.Padding.small : Constants.UI.Padding.big) {
                statColumn(value: viewModel.distance, label: "Distance")
                    .frame(maxWidth: .infinity)
                statColumn(value: viewModel.steps, label: "Steps")
                    .frame(maxWidth: .infinity)
                statColumn(value: viewModel.ascent, label: "Ascent")
                    .frame(maxWidth: .infinity)
            }

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
        // Combine all stats into a single VoiceOver element so users hear
        // them in one utterance and then move on to the controls.
        .accessibilityElement(children: .combine)
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

    /// Diameter of action/mic button circles. Bumped from 72/80 to 88/96
    /// so they feel generous and tappable in the expanded sheet (important
    /// for walkers with gloves, cold hands, or post-meditation drowsiness).
    private var controlButtonSize: CGFloat {
        isLargeText ? 96 : 88
    }

    private var micButton: some View {
        let isActive = viewModel.isRecordingVoice
        let size = controlButtonSize
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
        let size = controlButtonSize
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
