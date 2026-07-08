import SwiftUI

/// The threshold into a seek — distinct from onboarding's breath transition.
/// It teaches the seek language before the walk begins: mist gathers (the
/// fog to come), two sonar rings sound silently outward (the pulse to come),
/// and the mode's own line holds the center. Every animation is a one-shot
/// value change; the whole sequence runs once and completes.
struct SeekGatewayView: View {

    let onComplete: () -> Void

    @State private var mistOpacity: Double = 0
    @State private var mistScale: CGFloat = 0.85
    @State private var quoteOpacity: Double = 0
    @State private var ringOneScale: CGFloat = 0.25
    @State private var ringOneOpacity: Double = 0
    @State private var ringTwoScale: CGFloat = 0.25
    @State private var ringTwoOpacity: Double = 0

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        ZStack {
            Color.parchment
                .ignoresSafeArea()

            Circle()
                .fill(Color.fog)
                .frame(width: 260, height: 260)
                .blur(radius: 42)
                .opacity(mistOpacity)
                .scaleEffect(mistScale)

            ring(scale: ringOneScale, opacity: ringOneOpacity)
            ring(scale: ringTwoScale, opacity: ringTwoOpacity)

            Text(LS["Seek.Quote.1"])
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Constants.UI.Padding.breathingRoom)
                .opacity(quoteOpacity)
        }
        .onAppear { runGateway() }
    }

    private func ring(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(Color.stone.opacity(0.6), lineWidth: 1.5)
            .frame(width: 220, height: 220)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private func runGateway() {
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.4)) { quoteOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeOut(duration: 0.3)) { quoteOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { onComplete() }
            return
        }

        withAnimation(.easeInOut(duration: 1.4)) {
            mistOpacity = 0.5
            mistScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 1.6)) { quoteOpacity = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            HapticPattern.seekBreathIn.fire()
            ringOneOpacity = 0.5
            withAnimation(.easeOut(duration: 1.8)) {
                ringOneScale = 1.7
                ringOneOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            ringTwoOpacity = 0.4
            withAnimation(.easeOut(duration: 1.8)) {
                ringTwoScale = 1.7
                ringTwoOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.9) {
            withAnimation(.easeOut(duration: 1.2)) {
                mistOpacity = 0
                mistScale = 1.06
                quoteOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) { onComplete() }
    }
}

/// Seek speaks its own weather: the wander greetings name the path; these
/// name the search.
enum SeekVoice {
    static func greeting(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "A clear day for seeking"
        case .partlyCloudy: return "Seeking under shifting skies"
        case .overcast: return "Soft light on the search"
        case .lightRain: return "The rain joins your seeking"
        case .heavyRain: return "The sky seeks with you"
        case .thunderstorm: return "Thunder over the unknown"
        case .snow: return "Snow over the hidden way"
        case .fog: return "Fog seeking fog"
        case .wind: return "The wind knows the way"
        case .haze: return "The unknown behind its veil"
        }
    }
}
