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
}

struct HonorArrivalCard: Equatable {
    let wayTitle: String
    let voicesHeard: Int
    let placesPassed: Int
    /// The engine's numbers on the companion's timeline; persisted into the
    /// index link at save time so the summary can read them back.
    let theirSeconds: Double
    let yourSeconds: Double
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
            softTapEnabled: UserPreferences.honorSoftTapEnabled.value,
            voicesEnabled: UserPreferences.honorVoicesEnabled.value && UserPreferences.soundsEnabled.value
        )
        let player = honorSenses.makeVoicePlayer()
        // A voice that ends on its own leaves nothing playing, so the chip
        // must clear before the engine is asked for the next one — it may
        // answer immediately with another `.voiceStart`.
        player.onFinished = { [weak self] in
            guard let self, self.honorGeneration == generation else { return }
            self.activeVoice = nil
            self.isVoicePaused = false
            self.honorEngine?.voiceDidFinish()
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
        refreshHonorPins()
    }

    /// Rebuilds the map's Way inputs. The ghost line's geometry is fixed once
    /// the Way is accepted, so it is built once; the pins carry the heard
    /// state, which changes as voices play.
    func refreshHonorPins() {
        guard let way else { return }
        if honorWayState == nil {
            honorWayState = HonorWayState(
                id: way.id,
                routeCoordinates: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
        }
        honorPins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: heardVoiceIDs)
    }

    /// Where the companion is now: a binary search over the route on the
    /// engine's published frac, cheap enough for the map's per-frame read.
    /// The map itself throttles the dot to one move every two seconds.
    var companionCoordinate: CLLocationCoordinate2D? {
        honorEngine.map { $0.geometry.coordinate(atFrac: $0.companionFrac) }
    }

    /// Runs from both `stop()` and `cancel()`; the second call is a no-op.
    /// `honorArrival` deliberately survives — the summary reads it.
    func teardownHonor() {
        guard honorEngine != nil || wayVoicePlayer != nil else { return }
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
        reachedMomentIDs.removeAll()
        suggestedMeditationMinutes = nil
        pendingReplyOrigin = nil
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
        honorArrival = HonorArrivalCard(wayTitle: way.title, voicesHeard: heardVoiceIDs.count,
                                        placesPassed: reachedMomentIDs.count,
                                        theirSeconds: theirSeconds, yourSeconds: yourSeconds)
    }

    // MARK: - Cards, media, replies

    /// Whether a card is on screen at all — the walk screen's card layer
    /// spans the screen and must not take taps meant for the map when it
    /// carries nothing.
    var isShowingHonorCard: Bool {
        (honorArrival != nil && !honorArrivalCardDismissed) || !honorCards.isEmpty
    }

    func dismissTopCard() {
        if !honorCards.isEmpty { honorCards.removeFirst() }
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
        switch media {
        case .recording(let relativePath):
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return Self.resolvedMediaURL(docs.appendingPathComponent(relativePath), within: docs)
        case .file(let relative):
            guard let way else { return nil }
            let store = honorSenses.store()
            let url = store.mediaURL(for: way.id, relative: relative)
            return Self.resolvedMediaURL(url, within: store.mediaDirectory(for: way.id))
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

    /// Starts a recording answering `voice`. When that recording completes,
    /// `bindCompletedRecordings` (ActiveWalkViewModel.swift) has it, and
    /// `recordReplyIfPending` writes the mapping.
    func replyHere(to voice: WayMoment) {
        pendingReplyOrigin = voice
        if !isRecordingVoice { toggleVoiceRecording() }
        // `isRecordingVoice` only mirrors `voiceRecordingManagement.isRecording`
        // through an async main-queue sink, so it can't be trusted here yet —
        // reading the component directly gives the synchronous answer.
        // Denied permission, an inactive walk, or a recorder that failed to
        // open all leave it false; with nothing now in flight, no completed
        // recording will ever arrive to consume this origin.
        if !voiceRecordingManagement.isRecording {
            pendingReplyOrigin = nil
        }
    }

    /// The reply is filed under the origin voice's own index — the `n` in
    /// the `voice-n` ids `OwnWalkWayBuilder` writes — never its position in
    /// `moments`, which mixes every kind of moment together.
    func recordReplyIfPending(latestRecording: TempVoiceRecording) {
        guard let way, let origin = pendingReplyOrigin, let n = Self.originIndex(of: origin) else { return }
        pendingReplyOrigin = nil
        try? honorSenses.store().setReply(wayId: way.id, originN: n, relativePath: latestRecording.fileRelativePath)
    }

    /// The walker's earlier reply to `voice`, from a previous honoring of the
    /// same Way. A mapping whose recording is gone reads as no reply at all —
    /// `mediaURL(for:)` returns nil for a file that isn't there.
    func existingReplyURL(for voice: WayMoment) -> URL? {
        guard let way, let n = Self.originIndex(of: voice),
              let relative = honorSenses.store().replies(for: way.id)[n] else { return nil }
        return mediaURL(for: .recording(relativePath: relative))
    }

    /// The card's "your reply" button comes through here rather than touching
    /// the player directly: one voice plays at a time, so a Way voice must be
    /// given up rather than silently replaced under a chip that still claims
    /// it is playing. The engine gets its turn back when the reply ends,
    /// through the player's `onFinished`.
    func playReply(url: URL) {
        wayVoicePlayer?.stop()
        activeVoice = nil
        isVoicePaused = false
        wayVoicePlayer?.play(url: url, volume: Float(UserPreferences.voiceGuideVolume.value))
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

    // MARK: - Private

    private static let voiceIDPrefix = "voice-"
    private static let softTapCaptionSeconds: TimeInterval = 20

    /// The `n` in the `voice-n` ids `OwnWalkWayBuilder` writes — the index a
    /// reply is filed under. Nil for any other moment id.
    private static func originIndex(of moment: WayMoment) -> Int? {
        guard moment.id.hasPrefix(voiceIDPrefix) else { return nil }
        return Int(moment.id.dropFirst(voiceIDPrefix.count))
    }

    private func fireHonorHaptic(_ pattern: HapticPattern) {
        guard honorSenses.isAppActive() else { return }
        pattern.fire()
    }

    private var honorLocationFixes: AnyPublisher<CLLocation, Never> {
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
}
