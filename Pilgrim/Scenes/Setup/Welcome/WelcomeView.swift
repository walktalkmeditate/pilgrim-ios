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
                .padding(.bottom, Constants.UI.Padding.big)

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
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    private var footprintsView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            ForEach(0..<3, id: \.self) { index in
                FootprintShape()
                    .fill(Color.fog)
                    .frame(width: 30, height: 20)
                    .opacity(animation.footprintOpacities[index])
                    .offset(x: index % 2 == 0 ? -4 : 4)
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
