import SwiftUI

class WelcomeAnimationState: ObservableObject {

    @Published var showLogo = false
    @Published var isBreathing = false
    @Published var showQuote = false
    @Published var footprintOpacities: [Double] = [0, 0, 0]
    @Published var showButton = false
    @Published var showAmbient = false
    @Published var isExiting = false

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    func runEntrance() {
        if reduceMotion {
            showLogo = true
            isBreathing = false
            showQuote = true
            footprintOpacities = [1, 1, 1]
            showButton = true
            showAmbient = true
            return
        }

        // 0.5s — Logo fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 1.5)) { self.showLogo = true }
        }

        // 2.0s — Breathing starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isBreathing = true
        }

        // 2.5s — Quote fades in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) { self.showQuote = true }
        }

        // 3.5s, 4.2s, 4.9s — Footprints one by one
        let footprintTimes: [Double] = [3.5, 4.2, 4.9]
        for (index, time) in footprintTimes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) { [weak self] in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeInOut(duration: Constants.UI.Motion.appear)) {
                    self?.footprintOpacities[index] = 1.0
                }
            }
            // Fade to ghost after appearing (last holds longer)
            let fadeDelay = index == 2 ? 1.5 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + time + fadeDelay) { [weak self] in
                withAnimation(.easeOut(duration: 1.0)) {
                    self?.footprintOpacities[index] = 0.15
                }
            }
        }

        // 5.5s — Button slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { [weak self] in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeOut(duration: Constants.UI.Motion.gentle)) { self?.showButton = true }
        }

        // 6.0s — Ambient starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            withAnimation(.easeIn(duration: 2.0)) { self?.showAmbient = true }
        }
    }

    func runExit(completion: @escaping () -> Void) {
        isExiting = true

        if reduceMotion {
            showLogo = false
            showQuote = false
            footprintOpacities = [0, 0, 0]
            showButton = false
            showAmbient = false
            isBreathing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { completion() }
            return
        }

        // Stop breathing
        isBreathing = false

        // Button slides down
        withAnimation(.easeIn(duration: 0.3)) { showButton = false }

        // Footprints fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) { self?.footprintOpacities = [0, 0, 0] }
        }

        // Quote fades
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) { self?.showQuote = false }
        }

        // Logo fades + scales down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.5)) { self?.showLogo = false }
        }

        // Complete after total exit animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { completion() }
    }
}
