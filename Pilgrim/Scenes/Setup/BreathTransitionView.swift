import SwiftUI

struct BreathTransitionView: View {

    let onComplete: () -> Void

    @State private var screenScale: CGFloat = 1.0
    @State private var footprintOpacity: Double = 0
    @State private var warmthOpacity: Double = 0.02

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

        let stillness = 0.8

        DispatchQueue.main.asyncAfter(deadline: .now() + stillness) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                screenScale = 1.015
                footprintOpacity = 0.3
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + stillness + Constants.UI.Motion.breath) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        let exhaleStart = stillness + Constants.UI.Motion.breath + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + exhaleStart) {
            withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                self.screenScale = 1.0
                self.footprintOpacity = 0
                self.warmthOpacity = 0
            }
        }

        let completeTime = exhaleStart + Constants.UI.Motion.breath
        DispatchQueue.main.asyncAfter(deadline: .now() + completeTime) {
            self.onComplete()
        }
    }
}
