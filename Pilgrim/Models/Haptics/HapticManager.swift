import UIKit
import CoreHaptics

/// Shared Core Haptics engine for the app. Must live as a long-lived
/// instance — the previous implementation created a fresh `CHHapticEngine`
/// inside each pattern-firing function, and the engine was deallocated
/// before the pattern finished playing, so proximity haptics for whispers
/// and cairns silently never fired on device. Apple's own docs: "Keep
/// the engine as a property so it remains in memory during playback."
///
/// The engine is created lazily on first access, started once, and kept
/// alive for the lifetime of the app. `stoppedHandler` + `resetHandler`
/// handle system interruptions (phone calls, Siri, audio route changes)
/// by restarting the engine automatically.
final class HapticEngineHost {

    static let shared = HapticEngineHost()

    private(set) var engine: CHHapticEngine?
    private var isStarted = false

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // Keep running even when idle — we fire frequent short patterns
            // and restart latency would be audible/feelable.
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { [weak self] reason in
                print("[HapticEngine] stopped: \(reason.rawValue)")
                self?.isStarted = false
            }
            engine.resetHandler = { [weak self] in
                print("[HapticEngine] reset — restarting")
                self?.isStarted = false
                self?.startIfNeeded()
            }
            self.engine = engine
            startIfNeeded()
        } catch {
            print("[HapticEngine] init failed: \(error)")
        }
    }

    /// Starts the engine if it isn't already running. Safe to call
    /// repeatedly — a no-op when already started.
    func startIfNeeded() {
        guard let engine, !isStarted else { return }
        do {
            try engine.start()
            isStarted = true
        } catch {
            print("[HapticEngine] start failed: \(error)")
        }
    }

    /// Plays a Core Haptics pattern through the shared engine. Returns
    /// `true` on success, `false` if the engine is unavailable or the
    /// pattern failed to play. Callers should fall back to a simpler
    /// UIKit feedback generator when this returns `false`.
    ///
    /// Calls `engine.start()` unconditionally before playing. This is
    /// documented as idempotent on an already-running engine, and it
    /// makes the path self-healing if the engine was stopped by the
    /// system (background transition, audio session change) without
    /// our `stoppedHandler` being invoked in time to clear `isStarted`.
    @discardableResult
    func play(_ events: [CHHapticEvent]) -> Bool {
        guard let engine else { return false }
        do {
            try engine.start()
            isStarted = true
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            return true
        } catch {
            print("[HapticEngine] play failed: \(error)")
            return false
        }
    }
}

enum HapticPattern {
    case waypointDropped
    case whisperProximity
    case whisperPlaced
    case placementFailed
    case cairnProximity
    case stonePlaced(tier: Int)
    case seekTick(closeness: Double)
    case seekAligned(closeness: Double)
    case seekArrival
    case seekBreathIn
    case seekBreathOut

    func fire() {
        switch self {
        case .waypointDropped:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()

        case .whisperProximity:
            if !Self.playWhisperProximity() {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }

        case .whisperPlaced:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()

        case .placementFailed:
            // A short, sharp double-tap — distinct from the gentle "placed"
            // success haptic so a user with the phone in their pocket can
            // feel the difference even without looking at the screen.
            // Generic across whisper and stone placements; the on-screen
            // banner carries the noun.
            if !Self.playPlacementFailed() {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.warning)
            }

        case .cairnProximity:
            if !Self.playCairnProximity() {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
            }

        case .stonePlaced(let tier):
            if tier >= 5, Self.playDeepStone(tier: tier) {
                // Played via Core Haptics.
            } else {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
            }

        case .seekTick, .seekAligned, .seekArrival, .seekBreathIn, .seekBreathOut:
            fireSeek()
        }
    }

    /// Split from `fire()` to keep both switches inside the lint
    /// complexity budget.
    private func fireSeek() {
        switch self {
        case .seekTick(let closeness):
            if !Self.playSeekTick(closeness: closeness) {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.prepare()
                generator.impactOccurred()
            }

        case .seekAligned(let closeness):
            if !Self.playSeekAligned(closeness: closeness) {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
            }

        case .seekArrival:
            if !Self.playSeekArrival() {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }

        case .seekBreathIn:
            if !Self.playSeekBreath(rising: true) {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.prepare()
                generator.impactOccurred()
            }

        case .seekBreathOut:
            if !Self.playSeekBreath(rising: false) {
                let generator = UIImpactFeedbackGenerator(style: .soft)
                generator.prepare()
                generator.impactOccurred()
            }

        default:
            break
        }
    }

    private static func playWhisperProximity() -> Bool {
        let soft = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
        let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0.12),
            CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0.24)
        ]
        return HapticEngineHost.shared.play(events)
    }

    private static func playPlacementFailed() -> Bool {
        // Two sharp, slightly firmer taps in quick succession. Higher
        // sharpness than the success "placed" haptic and a tighter gap, so
        // the body learns to read it as "something didn't take" without any
        // visual cue.
        let firm = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55)
        let sharp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [firm, sharp], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [firm, sharp], relativeTime: 0.08)
        ]
        return HapticEngineHost.shared.play(events)
    }

    private static func playCairnProximity() -> Bool {
        let firm = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
        let sharp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [firm, sharp], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [firm, sharp], relativeTime: 0.15)
        ]
        return HapticEngineHost.shared.play(events)
    }

    private static func playSeekTick(closeness: Double) -> Bool {
        // Gentler than whisperProximity — a pocket metronome felt every
        // pulse for up to hours, not an alert. Intensity rides the engine's
        // closeness curve so skin and ear agree on distance.
        let intensity = Float(0.3 + 0.25 * min(max(closeness, 0), 1))
        let faint = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [faint, round], relativeTime: 0)
        ]
        return HapticEngineHost.shared.play(events)
    }

    private static func playSeekAligned(closeness: Double) -> Bool {
        // The "this way" heartbeat: two soft pulses, wider apart than
        // placementFailed's sharp pair so the body never confuses them.
        let intensity = Float(0.4 + 0.3 * min(max(closeness, 0), 1))
        let soft = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [soft, round], relativeTime: 0.18)
        ]
        return HapticEngineHost.shared.play(events)
    }

    private static func playSeekArrival() -> Bool {
        // Three rising soft taps — warm arrival, distinct from
        // cairnProximity's two firm sharp ones.
        let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        let steps: [(time: TimeInterval, intensity: Float)] = [(0, 0.4), (0.16, 0.55), (0.34, 0.7)]
        let events = steps.map { step in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: step.intensity),
                    round
                ],
                relativeTime: step.time
            )
        }
        return HapticEngineHost.shared.play(events)
    }

    private static func playSeekBreath(rising: Bool) -> Bool {
        // Slow soft swell for the in-hand stillness window, approximated as
        // two continuous segments. Each event stays under 2 s and nothing
        // loops — the caller repeats per breath and cancels on window exit.
        let round = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
        let quiet = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15)
        let full = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35)
        let first = rising ? quiet : full
        let second = rising ? full : quiet
        let events = [
            CHHapticEvent(eventType: .hapticContinuous, parameters: [first, round], relativeTime: 0, duration: 0.9),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [second, round], relativeTime: 0.9, duration: 0.9)
        ]
        return HapticEngineHost.shared.play(events)
    }

    private static func playDeepStone(tier: Int) -> Bool {
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
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0.15,
                duration: 0.2
            )
        ]
        return HapticEngineHost.shared.play(events)
    }
}
