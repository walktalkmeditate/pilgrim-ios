import AVFoundation
import UIKit

protocol AudioSessionApplying {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionApplying {}

final class AudioSessionCoordinator {

    static let shared = AudioSessionCoordinator()

    enum Mode {
        case idle
        case playbackOnly
        case recordingOnly
        case recordAndPlay
    }

    enum InterruptionEvent: Equatable {
        case began
        case ended(shouldResume: Bool)
    }

    private(set) var currentMode: Mode = .idle
    private var consumerModes: [String: Mode] = [:]
    private var interruptionObservers: [String: (InterruptionEvent) -> Void] = [:]
    private var isInterrupted = false
    private var interruptionGeneration = 0
    private let session: AudioSessionApplying
    private let queue = DispatchQueue(label: "AudioSessionCoordinator")

    /// How long `didBecomeActive` waits for a real `.ended` before falling back
    /// to a no-resume recovery. On a quick return (decline a call) iOS delivers
    /// both notifications within the same run-loop tick; the real `.ended`
    /// (which may carry `shouldResume: true`) must win.
    private let didBecomeActiveFallbackDelay: DispatchTimeInterval = .milliseconds(400)

    init(session: AudioSessionApplying = AVAudioSession.sharedInstance()) {
        self.session = session
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func activate(for mode: Mode, consumer: String) {
        queue.sync {
            consumerModes[consumer] = mode
            applyResolvedModeLocked()
        }
    }

    func deactivate(consumer: String) {
        queue.sync {
            guard consumerModes.removeValue(forKey: consumer) != nil else { return }
            applyResolvedModeLocked()
        }
    }

    /// Register with a stable id; re-registering the same id replaces the
    /// previous handler (so per-walk components don't accumulate). Events are
    /// delivered on the main queue with no coordinator lock held, so handlers
    /// may freely call activate/deactivate.
    func addInterruptionObserver(id: String, handler: @escaping (InterruptionEvent) -> Void) {
        queue.sync { interruptionObservers[id] = handler }
    }

    func removeInterruptionObserver(id: String) {
        queue.sync { _ = interruptionObservers.removeValue(forKey: id) }
    }

    // MARK: - Interruptions

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            interruptionDidBegin()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
            interruptionDidEnd(shouldResume: shouldResume)
        @unknown default:
            break
        }
    }

    private func interruptionDidBegin() {
        broadcast(.began) {
            self.isInterrupted = true
            self.interruptionGeneration += 1
        }
    }

    private func interruptionDidEnd(shouldResume: Bool) {
        broadcast(.ended(shouldResume: shouldResume)) {
            self.isInterrupted = false
            self.apply(self.resolvedMode(), force: true)
        }
        print("[AudioSessionCoordinator] Interruption ended (shouldResume: \(shouldResume))")
    }

    /// Apple documents that `.ended` is not always delivered (e.g. the user
    /// leaves for the interrupting app and returns much later). When the app
    /// becomes active while still interrupted, recover — but defer briefly so a
    /// near-simultaneous real `.ended` (the quick-return case, which may carry
    /// `shouldResume: true`) wins. Without the deferral, the fallback's
    /// `shouldResume: false` broadcast suppresses the legitimate resume and a
    /// consumer like the soundscape stays silent for the rest of the session.
    @objc private func handleDidBecomeActive() {
        let generation: Int? = queue.sync {
            isInterrupted ? interruptionGeneration : nil
        }
        guard let generation else { return }
        queue.asyncAfter(deadline: .now() + didBecomeActiveFallbackDelay) { [weak self] in
            self?.applyInterruptionFallback(generation: generation)
        }
    }

    /// Fires only if the captured interruption is still unresolved — a real
    /// `.ended` that arrived in the meantime cleared `isInterrupted` (and a new
    /// interruption bumped the generation), making this a no-op.
    private func applyInterruptionFallback(generation: Int) {
        var didRecover = false
        let observers: [(InterruptionEvent) -> Void] = queue.sync {
            guard isInterrupted, interruptionGeneration == generation else { return [] }
            isInterrupted = false
            didRecover = true
            apply(resolvedMode(), force: true)
            return Array(interruptionObservers.values)
        }
        guard didRecover else { return }
        deliver(.ended(shouldResume: false), to: observers)
    }

    /// Runs `stateChange` and snapshots observers under the lock, then
    /// delivers the event outside it — a handler that reacts by calling
    /// activate/deactivate re-enters through `queue.sync` without deadlock.
    private func broadcast(_ event: InterruptionEvent, stateChange: () -> Void) {
        let observers: [(InterruptionEvent) -> Void] = queue.sync {
            stateChange()
            return Array(interruptionObservers.values)
        }
        deliver(event, to: observers)
    }

    private func deliver(_ event: InterruptionEvent, to observers: [(InterruptionEvent) -> Void]) {
        DispatchQueue.main.async {
            for observer in observers { observer(event) }
        }
    }

    // MARK: - Arbitration

    /// Applied mode is the join of all live consumers' requirements:
    ///
    /// | live consumer modes                            | session state applied                  |
    /// |------------------------------------------------|----------------------------------------|
    /// | none                                           | inactive (idle)                        |
    /// | playbackOnly only                              | .playback + .mixWithOthers             |
    /// | recordingOnly only                             | .playAndRecord (speaker, BT-HFP)       |
    /// | recordAndPlay, or recordingOnly + playbackOnly | .playAndRecord + all options           |
    ///
    /// The mixed row is why this is a join and not a pure max: a
    /// `recordAndPlay > recordingOnly > playbackOnly` ladder would resolve
    /// {recordingOnly, playbackOnly} to recordingOnly and drop .mixWithOthers
    /// out from under the live playback consumer.
    private func resolvedMode() -> Mode {
        let modes = Set(consumerModes.values)
        let needsRecording = modes.contains(.recordingOnly) || modes.contains(.recordAndPlay)
        let needsMixedPlayback = modes.contains(.playbackOnly) || modes.contains(.recordAndPlay)
        switch (needsRecording, needsMixedPlayback) {
        case (true, true): return .recordAndPlay
        case (true, false): return .recordingOnly
        case (false, true): return .playbackOnly
        case (false, false): return .idle
        }
    }

    private func applyResolvedModeLocked() {
        // Between .began and .ended another app owns the session —
        // setActive(true) would fail and must not run. The consumer map keeps
        // tracking the desired state; .ended (or app re-activation when
        // .ended never arrives) applies it.
        guard !isInterrupted else { return }
        apply(resolvedMode())
    }

    private func apply(_ mode: Mode, force: Bool = false) {
        guard force || mode != currentMode else { return }
        currentMode = mode

        do {
            switch mode {
            case .idle:
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            case .playbackOnly:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true, options: [])
            case .recordingOnly:
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true, options: [])
            case .recordAndPlay:
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
                try session.setActive(true, options: [])
            }
        } catch {
            print("[AudioSessionCoordinator] Failed to apply mode \(mode): \(error)")
        }
    }
}

#if DEBUG
extension AudioSessionCoordinator {

    func _test_isConsumerActive(_ id: String) -> Bool {
        queue.sync { consumerModes[id] != nil }
    }

    func _test_simulateInterruptionBegan() {
        interruptionDidBegin()
    }

    func _test_simulateInterruptionEnded(shouldResume: Bool) {
        interruptionDidEnd(shouldResume: shouldResume)
    }

    /// Synchronous equivalent of `didBecomeActive` firing AND its fallback timer
    /// elapsing with no intervening real `.ended` — captures the generation the
    /// way the real handler does, then recovers immediately.
    func _test_simulateDidBecomeActive() {
        guard let generation = _test_captureDidBecomeActiveGeneration() else { return }
        applyInterruptionFallback(generation: generation)
    }

    /// Captures the interruption generation as `didBecomeActive` would, without
    /// scheduling the deferred fallback — lets a test interleave a real `.ended`
    /// before firing the stale fallback via `_test_fireInterruptionFallback`.
    func _test_captureDidBecomeActiveGeneration() -> Int? {
        queue.sync { isInterrupted ? interruptionGeneration : nil }
    }

    func _test_fireInterruptionFallback(generation: Int) {
        applyInterruptionFallback(generation: generation)
    }
}
#endif
