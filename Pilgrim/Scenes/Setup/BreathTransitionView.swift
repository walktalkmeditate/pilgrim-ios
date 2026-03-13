import SwiftUI

struct BreathTransitionView: View {

    let onComplete: () -> Void

    @State private var screenScale: CGFloat = 1.0
    @State private var contentOpacity: Double = 1.0
    @State private var footprintOpacity: Double = 0
    @State private var warmthOpacity: Double = 0.02
    @State private var mainContentOpacity: Double = 0
    @State private var mainContentOffset: CGFloat = 3

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            ZStack {
                Color.parchment
                Color.yellow.opacity(warmthOpacity)
            }
            .ignoresSafeArea()

            FootprintShape()
                .fill(Color.fog)
                .frame(width: 30, height: 20)
                .opacity(footprintOpacity)

            Color.clear
                .opacity(mainContentOpacity)
                .offset(y: mainContentOffset)
        }
        .scaleEffect(screenScale)
        .onAppear { runTransition() }
    }

    private func runTransition() {
        if reduceMotion {
            warmthOpacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onComplete() }
            return
        }

        // Inhale: scale up, content dissolves, footprint appears
        withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
            screenScale = 1.015
            contentOpacity = 0
            footprintOpacity = 0.3
        }

        // Peak: haptic pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.UI.Motion.breath) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        // Exhale: scale back, footprint fades, warmth fades, main content appears
        let exhaleStart = Constants.UI.Motion.breath + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + exhaleStart) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                self.screenScale = 1.0
                self.footprintOpacity = 0
                self.warmthOpacity = 0
                self.mainContentOpacity = 1
            }
        }

        // Settle: main content drifts up to final position
        let settleStart = exhaleStart + Constants.UI.Motion.breath
        DispatchQueue.main.asyncAfter(deadline: .now() + settleStart) {
            withAnimation(.easeOut(duration: Constants.UI.Motion.gentle)) {
                self.mainContentOffset = 0
            }
        }

        // Complete: trigger root state change
        let completeTime = settleStart + Constants.UI.Motion.gentle
        DispatchQueue.main.asyncAfter(deadline: .now() + completeTime) {
            self.onComplete()
        }
    }
}
