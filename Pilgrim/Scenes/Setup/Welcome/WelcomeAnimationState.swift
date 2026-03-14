import SwiftUI

class WelcomeAnimationState: ObservableObject {

    @Published var showLogo = false
    @Published var isBreathing = false
    @Published var showQuote = false
    @Published var footprintOpacities: [Double] = [0, 0, 0, 0, 0, 0, 0]
    @Published var showButton = false
    @Published var showAmbient = false
    @Published var isExiting = false

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    func runEntrance() {
        if reduceMotion {
            showLogo = true
            isBreathing = false
            showQuote = true
            footprintOpacities = Array(repeating: 1, count: 7)
            showButton = true
            showAmbient = true
            return
        }

        // 0.5s — Logo fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.isExiting else { return }
            withAnimation(.easeInOut(duration: 1.5)) { self.showLogo = true }
        }

        // 2.0s — Breathing starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.isExiting else { return }
            self.isBreathing = true
        }

        // 2.5s — Quote fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !self.isExiting else { return }
            withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) { self.showQuote = true }
        }

        // Footprints bottom-to-top (walking away), slow contemplative pace
        let footprintOrder = [6, 5, 4, 3, 2, 1, 0]
        let startTime = 3.5
        let stepInterval = 0.9

        for (orderIndex, footIndex) in footprintOrder.enumerated() {
            let time = startTime + Double(orderIndex) * stepInterval

            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                guard let self, !self.isExiting else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.footprintOpacities[footIndex] = 1.0
                }
            }

            let fadeDelay = footIndex == 0 ? 3.0 : 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + time + fadeDelay) { [weak self] in
                guard let self, !self.isExiting else { return }
                withAnimation(.easeOut(duration: 1.5)) {
                    self.footprintOpacities[footIndex] = 0.12
                }
            }
        }

        // Button after last footprint
        let buttonTime = startTime + Double(footprintOrder.count) * stepInterval + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonTime) { [weak self] in
            guard let self, !self.isExiting else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: Constants.UI.Motion.gentle)) { self.showButton = true }
        }

        // Ambient after button
        DispatchQueue.main.asyncAfter(deadline: .now() + buttonTime + 0.5) { [weak self] in
            guard let self, !self.isExiting else { return }
            withAnimation(.easeIn(duration: 2.0)) { self.showAmbient = true }
        }
    }

    func runExit(completion: @escaping () -> Void) {
        isExiting = true

        if reduceMotion {
            showLogo = false
            showQuote = false
            footprintOpacities = Array(repeating: 0, count: 7)
            showButton = false
            showAmbient = false
            isBreathing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion() }
            return
        }

        isBreathing = false
        withAnimation(.easeIn(duration: 0.3)) { showButton = false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) {
                self?.footprintOpacities = Array(repeating: 0, count: 7)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) { self?.showQuote = false }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.5)) { self?.showLogo = false }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { completion() }
    }
}
