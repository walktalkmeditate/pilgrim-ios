import SwiftUI

struct BreathTransitionView: View {

    let onComplete: () -> Void

    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.9
    @State private var warmthOpacity: Double = 0.02

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            ZStack {
                Color.parchment
                Color.yellow.opacity(warmthOpacity)
            }
            .ignoresSafeArea()

            PilgrimLogoView(size: 80)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
        }
        .onAppear { runTransition() }
    }

    private func runTransition() {
        if reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onComplete() }
            return
        }

        withAnimation(.easeInOut(duration: 1.0)) {
            logoOpacity = 1.0
            logoScale = 1.0
        }

        let inhaleStart = 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + inhaleStart) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                logoScale = 1.04
                warmthOpacity = 0.04
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + inhaleStart + Constants.UI.Motion.breath) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        let exhaleStart = inhaleStart + Constants.UI.Motion.breath + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + exhaleStart) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                logoScale = 0.95
                logoOpacity = 0
                warmthOpacity = 0
            }
        }

        let completeTime = exhaleStart + Constants.UI.Motion.breath
        DispatchQueue.main.asyncAfter(deadline: .now() + completeTime) {
            onComplete()
        }
    }
}
