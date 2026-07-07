import SwiftUI

/// The one seek setup question (R2): "How long do you have?" Four presets,
/// last choice preselected, first-seek-only safety caption (R21).
struct SeekDurationView: View {

    let showsSafetyCaption: Bool
    let onContinue: (Int) -> Void
    var onCancel: (() -> Void)?

    @State private var selectedMinutes: Int

    static let presetMinutes = [30, 60, 120, 180]

    init(
        showsSafetyCaption: Bool,
        onContinue: @escaping (Int) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.showsSafetyCaption = showsSafetyCaption
        self.onContinue = onContinue
        self.onCancel = onCancel
        _selectedMinutes = State(initialValue: Self.preselectedMinutes(
            lastUsed: UserPreferences.seekLastDurationMinutes.value
        ))
    }

    /// Snaps a stored value that no longer matches a preset (e.g. after a
    /// future preset change) to the closest one instead of leaving nothing
    /// selected.
    static func preselectedMinutes(lastUsed: Int) -> Int {
        presetMinutes.min(by: { abs($0 - lastUsed) < abs($1 - lastUsed) }) ?? 60
    }

    static func label(forMinutes minutes: Int) -> String {
        switch minutes {
        case 30: return LS.seekDuration30Min
        case 60: return LS.seekDuration1Hour
        case 120: return LS.seekDuration2Hours
        default: return LS.seekDuration3Hours
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(LS.seekDurationTitle)
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            VStack(spacing: Constants.UI.Padding.small) {
                ForEach(Self.presetMinutes, id: \.self) { minutes in
                    presetRow(minutes)
                }
            }
            .padding(.top, Constants.UI.Padding.big)

            if showsSafetyCaption {
                Text(LS.seekSafetyCaption)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
                    .padding(.top, Constants.UI.Padding.normal)
            }

            Spacer()

            bottomButtons
                .padding(.bottom, Constants.UI.Padding.big)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
    }

    private func presetRow(_ minutes: Int) -> some View {
        let isSelected = minutes == selectedMinutes
        return Button {
            selectedMinutes = minutes
            UserPreferences.seekLastDurationMinutes.value = minutes
        } label: {
            HStack {
                Text(Self.label(forMinutes: minutes))
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink.opacity(isSelected ? 1.0 : 0.7))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.stone)
                }
            }
            .padding(Constants.UI.Padding.normal)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                    .fill(Color.parchmentSecondary.opacity(isSelected ? 0.7 : 0.4))
            )
        }
    }

    private var bottomButtons: some View {
        HStack {
            if let onCancel {
                Button("Cancel") { onCancel() }
                    .font(Constants.Typography.button)
                    .foregroundColor(.fog)
            }

            Spacer()

            Button(LS.seekBegin) { onContinue(selectedMinutes) }
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        }
    }
}

// MARK: - Setup Flow Presentation

/// Owns every seek-setup presentation — the duration sheet, the breath
/// transition overlay, and the accuracy-declined alert — so that
/// `ActiveWalkView` (near its file_length ceiling) only applies one
/// modifier. Every behavior here is inert for wander walks: the stage
/// machine is born `.ready` and no presentation ever engages.
struct SeekSetupFlowModifier: ViewModifier {

    @ObservedObject var viewModel: ActiveWalkViewModel
    @Binding var showIntention: Bool
    let onCancelled: () -> Void

    @State private var showAccuracyDeclined = false

    private var showsDurationSheet: Binding<Bool> {
        Binding(
            get: { viewModel.seekSetupStage == .durationQuestion },
            set: { presented in
                // Only a swipe-down while still on the question is a
                // cancel; the Begin-driven dismissal has already advanced
                // the stage by the time SwiftUI writes false back.
                if !presented && viewModel.seekSetupStage == .durationQuestion {
                    viewModel.cancelSeekSetup()
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: showsDurationSheet) {
                SeekDurationView(
                    showsSafetyCaption: viewModel.seekShowsSafetyCaption,
                    onContinue: { minutes in
                        viewModel.advanceSeekSetup(durationMinutes: minutes)
                    },
                    onCancel: { viewModel.cancelSeekSetup() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.parchment.opacity(0.95))
            }
            .overlay {
                if viewModel.seekSetupStage == .transition {
                    BreathTransitionView {
                        viewModel.advanceSeekSetupTransitionComplete()
                    }
                    .transition(.opacity)
                }
            }
            .alert("Precise Location Needed", isPresented: $showAccuracyDeclined) {
                Button("OK", role: .cancel) { onCancelled() }
            } message: {
                Text(LS.seekAccuracyDeclined)
            }
            .onChange(of: viewModel.seekSetupStage) { _, stage in
                handleStageChange(stage)
            }
            .onAppear {
                guard viewModel.mode == .seek else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.beginSeekSetup()
                }
            }
    }

    private func handleStageChange(_ stage: SeekSetupStage) {
        switch stage {
        case .intention:
            // House sheet-swap spacing: presenting the intention sheet
            // while the duration sheet is still animating out drops the
            // presentation (same 0.3s rule as WalkOptionsSheet handoffs).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showIntention = true
            }
        case .cancelled(let reason):
            if reason == .accuracyDeclined {
                showAccuracyDeclined = true
            } else {
                onCancelled()
            }
        default:
            break
        }
    }
}
