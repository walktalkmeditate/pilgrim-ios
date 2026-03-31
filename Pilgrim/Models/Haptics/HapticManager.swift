import UIKit
import CoreHaptics

enum HapticPattern {
    case whisperProximity
    case whisperPlaced
    case cairnProximity
    case stonePlaced(tier: Int)

    func fire() {
        switch self {
        case .whisperProximity:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)

        case .whisperPlaced:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()

        case .cairnProximity:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred()

        case .stonePlaced(let tier):
            if tier >= 5, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                Self.fireDeepStoneHaptic(tier: tier)
            } else {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
            }
        }
    }

    private static func fireDeepStoneHaptic(tier: Int) {
        guard let engine = try? CHHapticEngine() else { return }
        do {
            try engine.start()

            let intensity = CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: min(1.0, 0.6 + Float(tier) * 0.06)
            )
            let sharpness = CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: max(0.2, 0.8 - Float(tier) * 0.1)
            )

            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.08),
                CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0.15, duration: 0.2),
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)

            engine.notifyWhenPlayersFinished { _ in .stopEngine }
        } catch {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}
