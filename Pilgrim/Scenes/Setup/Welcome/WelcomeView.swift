import SwiftUI

struct WelcomeView: View {

    @ObservedObject var viewModel: WelcomeViewModel
    @StateObject private var animation = WelcomeAnimationState()
    @State private var ambientOffset: CGSize = .zero

    var body: some View {
        ZStack {
            background
            content
        }
        .onAppear { animation.runEntrance() }
    }

    private var background: some View {
        ZStack {
            Color.parchment
            Color.yellow.opacity(0.02)
            if animation.showAmbient && !UIAccessibility.isReduceMotionEnabled {
                RadialGradient(
                    colors: [Color.yellow.opacity(0.03), Color.clear],
                    center: UnitPoint(
                        x: 0.5 + ambientOffset.width,
                        y: 0.5 + ambientOffset.height
                    ),
                    startRadius: 50,
                    endRadius: 300
                )
                .onAppear { startAmbientDrift() }
            }
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            PilgrimLogoView(size: 120, breathing: $animation.isBreathing)
                .opacity(animation.showLogo ? 1 : 0)
                .scaleEffect(animation.showLogo ? 1.0 : 0.85)
                .padding(.bottom, Constants.UI.Padding.big)

            Text(viewModel.currentQuote)
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .opacity(animation.showQuote ? 1 : 0)

            Spacer()

            footprintsView

            // Breath cue framing the walking-prints animation — turns dead
            // load time into intentional ritual so first-time users read
            // the wait as design, not latency.
            Text("Take a breath. We're right with you.")
                .font(Constants.Typography.caption.italic())
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .padding(.top, Constants.UI.Padding.small)
                .padding(.bottom, Constants.UI.Padding.big)
                .opacity(animation.showQuote ? 0.85 : 0)

            Button(action: beginTapped) {
                Text(LS["Welcome.Begin"])
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone)
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel("Begin your journey")
            .opacity(animation.showButton ? 1 : 0)
            .offset(y: animation.showButton ? 0 : 30)
            .disabled(animation.isExiting)

            // Privacy promise on-screen at sign-up. Surfacing this here
            // (vs. burying it in Settings) earns trust in the first 90s
            // and signals Pilgrim's no-accounts, no-tracking posture
            // before the user is asked for anything.
            Text("No accounts. Your recordings stay private — they never leave your device.")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .padding(.top, Constants.UI.Padding.normal)
                .opacity(animation.showButton ? 0.7 : 0)
                .accessibilityLabel("No accounts required. Your recordings stay private and never leave your device.")
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    private var footprintsView: some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            ForEach(0..<7, id: \.self) { index in
                let isLeft = index % 2 != 0
                let visible = animation.footprintOpacities[index] > 0.5

                FootprintShape()
                    .fill(Color.ink.opacity(0.18))
                    .frame(width: 22, height: 36)
                    .scaleEffect(x: isLeft ? -1 : 1)
                    .rotationEffect(.degrees(isLeft ? -12 : 12))
                    .opacity(animation.footprintOpacities[index])
                    .offset(x: isLeft ? -10 : 10)
                    .scaleEffect(visible ? 1.0 : 1.12)
                    .blur(radius: visible ? 0.4 : 1.2)
                    .animation(.spring(duration: 0.8, bounce: 0.15), value: visible)
                    .accessibilityHidden(true)
            }
        }
    }

    private func beginTapped() {
        guard !animation.isExiting else { return }
        animation.runExit {
            viewModel.beginAction()
        }
    }

    private func startAmbientDrift() {
        withAnimation(
            .easeInOut(duration: 15)
            .repeatForever(autoreverses: true)
        ) {
            ambientOffset = CGSize(width: 0.15, height: 0.1)
        }
    }
}
