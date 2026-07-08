import SwiftUI

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
    @State private var showGPSTimeout = false

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
                    SeekGatewayView {
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
            .alert("Still Reaching for the Sky", isPresented: $showGPSTimeout) {
                Button("OK", role: .cancel) { onCancelled() }
            } message: {
                Text(LS.seekGPSTimeout)
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
            switch reason {
            case .accuracyDeclined:
                showAccuracyDeclined = true
            case .gpsTimeout:
                showGPSTimeout = true
            case .userDismissed:
                onCancelled()
            }
        default:
            break
        }
    }
}
