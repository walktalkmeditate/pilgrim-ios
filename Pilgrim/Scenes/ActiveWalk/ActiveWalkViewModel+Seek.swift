import Combine
import CoreLocation
import Foundation
import UIKit

/// Seam over `SeekSoundPlayer` so VM tests can spy the ritual audio without
/// touching the audio session.
protocol SeekSoundPlaying: AnyObject {
    func prepare()
    func playPing(aligned: Bool)
    func playBowl()
    func stop()
}

extension SeekSoundPlayer: SeekSoundPlaying {}

/// Injectable seek side-effect hooks. Production defaults reach the real
/// sound player, whisper catalog, and application state; tests swap spies in.
struct SeekSenses {
    var makeSoundPlayer: () -> SeekSoundPlaying = { SeekSoundPlayer() }
    var pickRevealWhisper: () -> WhisperDefinition? = { ActiveWalkViewModel.randomDownloadedRevealWhisper() }
    var playWhisper: (WhisperDefinition) -> Void = { WhisperPlayer.shared.play($0) }
    /// Haptics only render in the foreground (iOS discards background CoreHaptics);
    /// the gate lives here so event routing can stay in the view model.
    var isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    var revealWhisperDelay: TimeInterval = 2.5
}

// MARK: - Seek Engine Lifecycle (F2/F3)

extension ActiveWalkViewModel {

    static let seekChainFixAccuracyMeters = 50.0

    /// Stage-driven engine boot: the GPS-lock hold starts with the breath
    /// transition so the chain is usually ready before the walker opens
    /// their eyes.
    func bindSeekLifecycle() {
        $seekSetupStage
            .removeDuplicates()
            .sink { [weak self] stage in
                guard stage == .transition else { return }
                self?.beginSeekGPSLock()
            }
            .store(in: &seekCancellables)
    }

    func beginSeekGPSLock() {
        guard mode == .seek, seekEngine == nil else { return }
        seekGeneration += 1
        let generation = seekGeneration

        $currentLocation
            .compactMap { $0 }
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= Self.seekChainFixAccuracyMeters }
            .prefix(1)
            .sink { [weak self] sample in
                guard let self, self.seekGeneration == generation else { return }
                self.startSeekEngine(from: sample)
            }
            .store(in: &seekCancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.seekGPSLockTimeoutSeconds) { [weak self] in
            guard let self, self.seekGeneration == generation else { return }
            self.failSeekSetupGPSLock()
        }
    }

    func startSeekEngine(from sample: TempRouteDataSample) {
        guard mode == .seek, seekEngine == nil else { return }
        seekGeneration += 1

        let start = SeekPoint(latitude: sample.latitude, longitude: sample.longitude)
        var rng = SystemRandomNumberGenerator()
        let chain = SeekChainGenerator.generate(
            durationMinutes: seekDurationMinutes ?? UserPreferences.seekLastDurationMinutes.value,
            start: start,
            using: &rng
        )
        let engine = SeekEngine(chain: chain, home: start)

        let sound = seekSenses.makeSoundPlayer()
        sound.prepare()
        seekSound = sound

        // Locations mirror liveStats.currentLocation (the same feed
        // ProximityDetectionService binds to) via the published mirror, so
        // tests can drive the engine by writing `currentLocation`.
        engine.bind(
            locations: seekLocationFixes,
            stepCounts: builder.stepsPublisher.compactMap { $0 }.eraseToAnyPublisher(),
            builderStatus: builder.statusPublisher,
            powerTier: sessionGuard?.powerTierPublisher
                ?? Just(WalkSessionGuard.PowerTier.normal).eraseToAnyPublisher()
        )

        // The engine is main-confined, so both sinks below fire on main
        // without a scheduler hop — keeping the arrival commit synchronous
        // with the engine's state transition.
        engine.events
            .sink { [weak self] event in self?.handleSeekEvent(event) }
            .store(in: &seekCancellables)

        engine.$chain
            .combineLatest(engine.$activeIndex, engine.$phase, engine.$distanceToActiveMeters)
            .sink { [weak self] chain, activeIndex, phase, distance in
                self?.updateSeekFog(chain: chain, activeIndex: activeIndex, phase: phase, distance: distance)
            }
            .store(in: &seekCancellables)

        seekEngine = engine
    }

    func teardownSeek() {
        seekGeneration += 1
        seekCancellables.removeAll()
        seekEngine?.stop()
        seekSound?.stop()
    }

    // MARK: - Event routing

    /// The single seam between engine events and the senses. Internal so
    /// tests can drive events directly (house pattern from U2).
    func handleSeekEvent(_ event: SeekEngineEvent) {
        switch event {
        case .pulse(let aligned, _):
            seekPulseToken += 1
            seekSound?.playPing(aligned: aligned)
            fireSeekHaptic(aligned ? .seekAligned : .seekTick)

        case .arrived(let clearingIndex):
            // The persistence commit happens before any ritual effect so an
            // interruption mid-ritual can never lose the arrival.
            recordSeekArrival(clearingIndex: clearingIndex)
            fireSeekHaptic(.seekArrival)

        case .stillnessBegan:
            fireSeekHaptic(.seekBreathIn)

        case .revealedNext:
            seekSound?.playBowl()
            scheduleSeekRevealWhisper()

        case .seekComplete:
            seekSound?.playBowl()
        }
    }

    func writeSeekMarkerEventIfNeeded() {
        guard mode == .seek else { return }
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekMode, timestamp: Date()))
    }

    private func recordSeekArrival(clearingIndex: Int) {
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .seekArrival, timestamp: Date()))
        addWaypoint(
            label: SeekPersistence.arrivalWaypointLabel(clearingOrdinal: clearingIndex + 1),
            icon: SeekPersistence.arrivalWaypointIcon
        )
    }

    /// R17 "Seek anew": regenerates the remainder of the chain from the
    /// walker's current position. Uncapped by design.
    func seekAnewRequested() {
        guard let engine = seekEngine else { return }
        let point: SeekPoint
        if let sample = currentLocation {
            point = SeekPoint(latitude: sample.latitude, longitude: sample.longitude)
        } else if let last = routeCoordinates.last {
            point = SeekPoint(latitude: last.latitude, longitude: last.longitude)
        } else {
            return
        }
        engine.seekAnew(currentLocation: point)
    }

    var isSeekComplete: Bool { seekEngine?.phase == .complete }

    // MARK: - Reveal ritual (R15)

    /// One whisper from the walker's already-downloaded catalog, played
    /// after the bowl has had room to ring. No whisper available → the
    /// ritual proceeds without it. Generation-guarded so teardown or a
    /// superseding reveal cancels the pending play.
    private func scheduleSeekRevealWhisper() {
        guard UserPreferences.soundsEnabled.value else { return }
        seekGeneration += 1
        let generation = seekGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + seekSenses.revealWhisperDelay) { [weak self] in
            guard let self, self.seekGeneration == generation else { return }
            guard let whisper = self.seekSenses.pickRevealWhisper() else { return }
            self.seekSenses.playWhisper(whisper)
        }
    }

    static func randomDownloadedRevealWhisper() -> WhisperDefinition? {
        let whispers = WhisperManifestService.shared.manifest?.whispers ?? []
        return whispers
            .filter { $0.retiredAt == nil && WhisperPlayer.shared.isAvailable($0) }
            .randomElement()
    }

    // MARK: - Derived senses

    private func fireSeekHaptic(_ pattern: HapticPattern) {
        guard seekSenses.isAppActive() else { return }
        pattern.fire()
    }

    private func updateSeekFog(
        chain: SeekChain,
        activeIndex: Int,
        phase: SeekEnginePhase,
        distance: Double?
    ) {
        let state = SeekFogModel.fogState(
            chain: chain,
            activeIndex: activeIndex,
            phase: phase,
            distanceToActiveMeters: distance,
            previousActiveBucket: previousActiveFogBucket
        )
        previousActiveFogBucket = state.activeFogBucket
        if state != seekFogState {
            seekFogState = state
        }
    }

    private var seekLocationFixes: AnyPublisher<CLLocation, Never> {
        $currentLocation
            .compactMap { sample -> CLLocation? in
                guard let sample else { return nil }
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                    altitude: sample.altitude,
                    horizontalAccuracy: sample.horizontalAccuracy,
                    verticalAccuracy: sample.verticalAccuracy,
                    course: sample.direction,
                    speed: sample.speed,
                    timestamp: sample.timestamp
                )
            }
            .eraseToAnyPublisher()
    }
}
