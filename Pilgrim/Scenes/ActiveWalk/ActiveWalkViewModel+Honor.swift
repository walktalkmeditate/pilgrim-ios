import Combine
import CoreLocation
import Foundation
import UIKit

/// Injectable honor side effects, like SeekSenses.
struct HonorSenses {
    var makeVoicePlayer: () -> WayVoicePlaying = { WayVoicePlayer.shared }
    /// Haptics only render in the foreground; the gate lives here so event
    /// routing can stay in the view model.
    var isAppActive: () -> Bool = { UIApplication.shared.applicationState == .active }
    var store: () -> WayStore = { WayStore.shared }
    var makeHeadingProvider: () -> HeadingProviding = { HeadingProvider() }
}

struct HonorArrivalCard: Equatable {
    let wayTitle: String
    let voicesHeard: Int
    let placesPassed: Int
    /// The engine's numbers on the companion's timeline; persisted into the
    /// index link at save time so the summary can read them back. A stage
    /// carries the package's own active seconds as `theirSeconds` too, but
    /// the summary ignores them for a stage — there is no companion to
    /// compare arrival against.
    let theirSeconds: Double
    let yourSeconds: Double
    /// Set only for a pilgrimage stage; the card then speaks of the stage
    /// rather than of another walker.
    let stageName: String?
    let distanceWalkedMeters: Double
    /// The stage's closing line, present only once arrival fired on a stage.
    /// Optional and last, like `WayMoment.place` and `.transcript`.
    var closing: String?

    var isStage: Bool { stageName != nil }
}

// MARK: - Honor Engine Lifecycle

extension ActiveWalkViewModel {

    func writeHonorMarkerEventIfNeeded() {
        guard mode == .honor, way != nil else { return }
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date()))
    }

    func startHonorEngineIfNeeded() {
        guard mode == .honor, let way, honorEngine == nil else { return }
        // Nothing queued before Begin belongs to this walk.
        honorCards.removeAll()
        honorGeneration += 1
        let generation = honorGeneration
        let engine = HonorEngine(
            way: way,
            // A stage has no other walker to be off the way *from*; the soft
            // tap and the companion dot are both about someone else.
            softTapEnabled: UserPreferences.honorSoftTapEnabled.value && !way.isPilgrimageStage,
            voicesEnabled: UserPreferences.honorVoicesEnabled.value && UserPreferences.soundsEnabled.value
        )
        let player = honorSenses.makeVoicePlayer()
        // A voice that ends on its own leaves nothing playing, so the chip
        // must clear before the engine is asked for the next one — it may
        // answer immediately with another `.voiceStart`.
        player.onFinished = { [weak self] in
            guard let self, self.honorGeneration == generation else { return }
            let finished = self.activeVoice
            self.activeVoice = nil
            self.isVoicePaused = false
            self.honorEngine?.voiceDidFinish()
            if let finished { self.retireCardLater(finished) }
        }
        wayVoicePlayer = player

        engine.bind(
            locations: honorLocationFixes,
            activeDuration: $activeDurationSeconds.eraseToAnyPublisher(),
            isPaused: $status.map { $0 != .recording }.eraseToAnyPublisher(),
            isMeditating: $isMeditating.eraseToAnyPublisher(),
            isRecordingVoice: $isRecordingVoice.eraseToAnyPublisher(),
            externalAudio: AudioPriorityQueue.shared.$isPlayingWhisper.eraseToAnyPublisher()
        )
        // The engine's own streams already hop to main, so its events reach
        // this sink on main without another hop.
        engine.events
            .sink { [weak self] event in self?.handleHonorEvent(event) }
            .store(in: &honorCancellables)
        honorEngine = engine
        // The compass lives exactly as long as the engine: started here,
        // stopped in teardown with the rest of the honor state.
        let heading = honorSenses.makeHeadingProvider()
        heading.headingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.headingDegrees = $0 }
            .store(in: &honorCancellables)
        heading.start()
        honorHeading = heading
        bindMarkPins()
        refreshHonorPins()
    }

    /// Rebuilds the map's Way inputs. The ghost line's geometry is fixed once
    /// the Way is accepted, so it is built once; the pins carry the heard
    /// state, which changes as voices play.
    func refreshHonorPins() {
        guard let way else { return }
        if honorWayState == nil {
            honorWayState = HonorWayState(way: way)
        }
        honorPins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: heardVoiceIDs)
    }

    /// Where the companion is now: a binary search over the route on the
    /// engine's published frac, cheap enough for the map's per-frame read.
    /// The map itself throttles the dot to one move every two seconds.
    /// A stage has no companion — its clock is synthesized so the engine
    /// works unchanged, and nothing draws it.
    var companionCoordinate: CLLocationCoordinate2D? {
        guard way?.isPilgrimageStage != true else { return nil }
        return honorEngine.map { $0.geometry.coordinate(atFrac: $0.companionFrac) }
    }

    /// Runs from both `stop()` and `cancel()`; the second call is a no-op.
    /// `honorArrival` deliberately survives — the summary reads it.
    func teardownHonor() {
        guard honorEngine != nil || wayVoicePlayer != nil else { return }
        if let engine = honorEngine, engine.isAnchoredOnWay {
            honorStageOutcome = HonorStageOutcome(progressFrac: engine.progressFrac,
                                                  arrived: engine.phase == .arrived)
        }
        honorGeneration += 1
        honorCancellables.removeAll()
        honorEngine?.stop()
        honorEngine = nil
        wayVoicePlayer?.stop()
        // The player outlives this walk (it's the shared singleton in
        // production); drop the closure here so it can't call back into a
        // torn-down view model once a future walk replaces it.
        wayVoicePlayer?.onFinished = nil
        wayVoicePlayer = nil
        activeVoice = nil
        isVoicePaused = false
        honorCards.removeAll()
        honorMarkPins.removeAll()
        markPinAnchor = nil
        reachedMomentIDs.removeAll()
        suggestedMeditationMinutes = nil
        pendingReplyOrigin = nil
        touchedCardIDs.removeAll()
        voiceRate = 1
        honorFocus = nil
        honorHeading?.stop()
        honorHeading = nil
        headingDegrees = nil
        softTapCaption = nil
    }

    // MARK: - Events

    func handleHonorEvent(_ event: HonorEngineEvent) {
        switch event {
        case .momentReached(let moment):
            if !honorCards.contains(moment) { honorCards.append(moment) }
            reachedMomentIDs.insert(moment.id)
            fireHonorHaptic(.waypointDropped)

        case .voiceStart(let moment):
            startVoice(moment)

        case .voicePause:
            isVoicePaused = true
            wayVoicePlayer?.pause()

        case .voiceResume:
            isVoicePaused = false
            wayVoicePlayer?.resume()

        case .voiceDropped(let moment):
            if activeVoice == moment {
                wayVoicePlayer?.stop()
                activeVoice = nil
                isVoicePaused = false
            }

        case .softTap(let meters):
            showSoftTapCaption(meters: meters)
            fireHonorHaptic(.honorOffWay)

        case .markAhead(let mark, let meters):
            showMarkCaption(mark: mark, meters: meters)
            fireHonorHaptic(.honorWaterAhead)

        case .arrived(let theirSeconds, let yourSeconds):
            recordHonorArrival(theirSeconds: theirSeconds, yourSeconds: yourSeconds)
            fireHonorHaptic(.honorArrival)
        }
    }

    /// A voice whose file is gone was never heard: hand the turn straight
    /// back to the engine so the next one can start.
    private func startVoice(_ moment: WayMoment) {
        guard case .voice(_, _, let kind, let media) = moment.kind, let url = mediaURL(for: media) else {
            honorEngine?.voiceDidFinish()
            return
        }
        activeVoice = moment
        isVoicePaused = false
        heardVoiceIDs.insert(moment.id)
        refreshHonorPins()
        wayVoicePlayer?.play(url: url, volume: Self.voiceVolume(for: kind))
        // The voice's own card rises with it — the waveform, the place, the
        // reply — and retires itself after the voice unless the walker
        // touches it, so an unanswered voice never leaves a card to close.
        showCard(for: moment)
    }

    /// The caption retires itself, so a walker who rejoins the Way is never
    /// left reading a distance they have already closed. Generation-guarded
    /// like every other honor `asyncAfter`: teardown bumps the generation and
    /// this write becomes a no-op.
    private func showSoftTapCaption(meters: Double) {
        // `Int(_:)` traps on an infinity; the engine already clamps, and this
        // is the last line of defence before the number reaches the screen.
        softTapCaption = "off the way · \(Int(min(meters.isFinite ? meters : 0, 999_999))) m"
        let generation = honorGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.softTapCaptionSeconds) { [weak self] in
            guard let self, self.honorGeneration == generation else { return }
            self.softTapCaption = nil
        }
    }

    /// The persistence commit happens before any ritual effect, as in Seek.
    private func recordHonorArrival(theirSeconds: Double, yourSeconds: Double) {
        guard let way else { return }
        builder.addWorkoutEvent(TempWalkEvent(uuid: nil, eventType: .honorArrival, timestamp: Date()))
        addWaypoint(label: HonorPersistence.arrivalWaypointLabel(wayTitle: way.title),
                    icon: HonorPersistence.arrivalWaypointIcon)
        honorArrival = HonorArrivalCard(
            wayTitle: way.title, voicesHeard: heardVoiceIDs.count,
            placesPassed: reachedMomentIDs.count,
            theirSeconds: theirSeconds, yourSeconds: yourSeconds,
            stageName: way.stage?.name,
            distanceWalkedMeters: honorEngine?.distanceWalkedMeters ?? 0,
            closing: way.stage?.closing)
    }

    // MARK: - Cards and media

    /// Whether a card is on screen at all — the walk screen's card layer
    /// spans the screen and must not take taps meant for the map when it
    /// carries nothing.
    var isShowingHonorCard: Bool {
        (honorArrival != nil && !honorArrivalCardDismissed) || !honorCards.isEmpty
    }

    /// Straight-line metres from the walker's last fix to the moment's place,
    /// nil before the first fix. Cheap enough for the card's subline.
    func distanceToMoment(_ moment: WayMoment) -> Double? {
        guard let here = currentLocation, let there = coordinate(of: moment) else { return nil }
        return CLLocation(latitude: here.latitude, longitude: here.longitude)
            .distance(from: CLLocation(latitude: there.latitude, longitude: there.longitude))
    }

    /// Degrees clockwise from the walker's heading to the moment: the
    /// direction tick. Nil until both a fix and a settled compass exist.
    func relativeBearing(to moment: WayMoment) -> Double? {
        guard let here = currentLocation, let heading = headingDegrees, let there = coordinate(of: moment) else { return nil }
        let bearing = WayGeometry.bearing(from: CLLocationCoordinate2D(latitude: here.latitude, longitude: here.longitude), to: there)
        return (bearing - heading + 360).truncatingRemainder(dividingBy: 360)
    }

    /// One tap sends the map to the moment, the next brings it home; a
    /// different moment's header jumps straight to that moment.
    func toggleFocus(on moment: WayMoment) {
        guard let there = coordinate(of: moment) else { return }
        if let focus = honorFocus, focus.latitude == there.latitude, focus.longitude == there.longitude {
            honorFocus = nil
        } else {
            honorFocus = there
        }
    }

    /// A moment recorded with its own coordinate uses it; one placed only
    /// along the line borrows the line's point at its frac.
    private func coordinate(of moment: WayMoment) -> CLLocationCoordinate2D? {
        if let at = moment.at { return CLLocationCoordinate2D(latitude: at.lat, longitude: at.lon) }
        return honorEngine?.geometry.coordinate(atFrac: moment.frac)
    }

    /// The seconds a finished voice's card stays before retiring on its own.
    static let cardRetireSeconds: TimeInterval = 20

    func touchCard(_ moment: WayMoment) {
        touchedCardIDs.insert(moment.id)
    }

    /// A voice card the walker never touched leaves by itself once its voice
    /// has ended; one they touched (played again, replied to) waits for them.
    func retireIfUntouched(_ moment: WayMoment) {
        guard !touchedCardIDs.contains(moment.id), activeVoice != moment else { return }
        honorCards.removeAll { $0 == moment }
    }

    private func retireCardLater(_ moment: WayMoment) {
        let generation = honorGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cardRetireSeconds) { [weak self] in
            guard let self, self.honorGeneration == generation else { return }
            self.retireIfUntouched(moment)
        }
    }

    func dismissTopCard() {
        if !honorCards.isEmpty { honorCards.removeFirst() }
        // A card that flew the map somewhere takes the map home when it goes.
        honorFocus = nil
    }

    /// A tapped pin jumps the queue; pending cards resume after it.
    func showCard(for moment: WayMoment) {
        honorCards.removeAll { $0 == moment }
        honorCards.insert(moment, at: 0)
    }

    /// Ambience is the sound of a place, not a voice: it plays once at half
    /// the voice level on entry. A continuous bed inside its span is deferred
    /// (one player at a time, per the resource-safety rules).
    static func voiceVolume(for kind: VoiceKind) -> Float {
        let base = Float(UserPreferences.voiceGuideVolume.value)
        return kind == .ambient ? base * 0.5 : base
    }

    func mediaURL(for media: WayMedia) -> URL? {
        guard let way else { return nil }
        return Self.localMediaURL(for: media, wayId: way.id, store: honorSenses.store())
    }

    /// Where a moment's media lives on this phone, or nil when the file is
    /// not (yet) here. Shared by the walk's cards and the overview's preview.
    static func localMediaURL(for media: WayMedia, wayId: String, store: WayStore) -> URL? {
        switch media {
        case .recording(let relativePath):
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return resolvedMediaURL(docs.appendingPathComponent(relativePath), within: docs)
        case .file(let relative):
            let url = store.mediaURL(for: wayId, relative: relative)
            return resolvedMediaURL(url, within: store.mediaDirectory(for: wayId))
        case .photoAsset:
            return nil
        }
    }

    /// A relative path comes from a Way's own JSON — a share file or a
    /// hand-edited own-walk record — so a `../` component must not be able
    /// to walk it outside its base directory. Standardizing collapses any
    /// such component before the containment check.
    private static func resolvedMediaURL(_ url: URL, within base: URL) -> URL? {
        let resolved = url.standardizedFileURL
        let baseComponents = base.standardizedFileURL.pathComponents
        guard resolved.pathComponents.count > baseComponents.count,
              Array(resolved.pathComponents.prefix(baseComponents.count)) == baseComponents else { return nil }
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
    }

    func startMeditation(minutes: Int) {
        suggestedMeditationMinutes = minutes
        startMeditation()
    }

    /// From the card or the chip: pause or resume the active voice, or replay
    /// another voice outside the engine's queue. A heard voice must mean a
    /// played voice, so this is a no-op before the walk has a player at all —
    /// otherwise a pin tap before Begin could mark a voice heard with
    /// nothing behind it to play.
    func togglePlayback(of moment: WayMoment) {
        guard let player = wayVoicePlayer else { return }
        if moment == activeVoice {
            if isVoicePaused { player.resume() } else { player.pause() }
            isVoicePaused.toggle()
            return
        }
        guard case .voice(_, _, let kind, let media) = moment.kind, let url = mediaURL(for: media) else { return }
        player.stop()
        activeVoice = moment
        isVoicePaused = false
        heardVoiceIDs.insert(moment.id)
        refreshHonorPins()
        player.play(url: url, volume: Self.voiceVolume(for: kind))
    }

    /// Scrubbing a card whose voice isn't the one playing starts that voice
    /// first — the walker asked for a spot in it, not for silence.
    func seekVoice(_ moment: WayMoment, toFraction fraction: Double) {
        if moment != activeVoice { togglePlayback(of: moment) }
        guard moment == activeVoice else { return }
        wayVoicePlayer?.seek(toFraction: fraction)
    }

    /// 1× → 1.25× → 1.5× → 2× → 1×, the same ladder as the post-walk player.
    func cycleVoiceRate() {
        let rates = WayVoicePlayer.rates
        let next = rates[((rates.firstIndex(of: voiceRate) ?? 0) + 1) % rates.count]
        voiceRate = next
        wayVoicePlayer?.setRate(next)
    }

    func skipVoice() {
        guard activeVoice != nil else { return }
        wayVoicePlayer?.stop()
        activeVoice = nil
        isVoicePaused = false
        honorEngine?.voiceDidFinish()
    }

    // MARK: - Live Activity glance

    /// Computed here — never in the widget, which has no sensors.
    func currentHonorGlance() -> HonorGlanceState? {
        guard let engine = honorEngine else { return nil }
        return HonorGlanceState(
            distanceRemainingBucketMeters: SeekGlanceModel.distanceBucket(forMeters: engine.distanceRemainingMeters),
            isOnWay: engine.isOnWay, isArrived: engine.phase == .arrived)
    }

    /// The walker's fixes as `CLLocation`s. Not private: the mark pins in
    /// `ActiveWalkViewModel+MarkPins.swift` follow the same stream rather
    /// than re-deriving coordinates from the raw sample.
    var honorLocationFixes: AnyPublisher<CLLocation, Never> {
        $currentLocation
            .compactMap { sample -> CLLocation? in
                guard let sample else { return nil }
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: sample.latitude, longitude: sample.longitude),
                    altitude: sample.altitude, horizontalAccuracy: sample.horizontalAccuracy,
                    verticalAccuracy: sample.verticalAccuracy, course: sample.direction,
                    speed: sample.speed, timestamp: sample.timestamp)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Private

    /// Not private: the water notice borrows this slot, so it borrows this life.
    static let softTapCaptionSeconds: TimeInterval = 20

    private func fireHonorHaptic(_ pattern: HapticPattern) {
        guard honorSenses.isAppActive() else { return }
        pattern.fire()
    }
}
