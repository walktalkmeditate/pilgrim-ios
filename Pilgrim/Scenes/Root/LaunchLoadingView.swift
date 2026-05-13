import SwiftUI

/// Frames the ~2-3s DataManager.setup window as ritual rather than load.
/// Replaces the bland `ProgressView("Loading...")` that previously rendered
/// here. The user sees the breathing pilgrim mark + a single breath cue —
/// when `.done` fires, this view is replaced by the full WelcomeView (which
/// has its own entrance animation, so we deliberately don't animate
/// walking prints here to avoid two-prints-in-a-row dissonance).
struct LaunchLoadingView: View {

    @State private var breathing = true

    var body: some View {
        ZStack {
            Color.parchment
                .ignoresSafeArea()

            VStack(spacing: Constants.UI.Padding.normal) {
                PilgrimLogoView(size: 96, breathing: $breathing)

                Text("Take a breath. We're right with you.")
                    .font(Constants.Typography.caption.italic())
                    .foregroundColor(.fog.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Constants.UI.Padding.big)
            }
        }
    }
}
