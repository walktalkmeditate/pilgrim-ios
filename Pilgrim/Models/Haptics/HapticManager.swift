import UIKit
import CoreHaptics

enum HapticPattern {
    case waypointDropped
    case whisperProximity
    case whisperPlaced
    case cairnProximity
    case stonePlaced(tier: Int)

    func fire() {
        switch self {
        case .waypointDropped:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()

        case .whisperProximity:
            if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                Self.fireWhisperProximityHaptic()
            } else {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }

        case .whisperPlaced:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()

        case .cairnProximity:
            if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                Self.fireCairnProximityHaptic()
            } else {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
            }

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

    private static func fireWhisperProximityHaptic() {
        guard let engine = try? CHHapticEngine() else { return }
        do {
            try engine.start()
            let soft = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
            let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0.12),
                CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0.24)
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            engine.notifyWhenPlayersFinished { _ in .stopEngine }
        } catch {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }

    private static func fireCairnProximityHaptic() {
        guard let engine = try? CHHapticEngine() else { return }
        do {
            try engine.start()
            let firm = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
            let sharp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [firm, sharp], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [firm, sharp], relativeTime: 0.15)
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
                CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0.15, duration: 0.2)
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
