import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

final class ActiveWalkHonorTests: XCTestCase {

    private final class SpyVoicePlayer: WayVoicePlaying {
        var onFinished: (() -> Void)?
        var played: [URL] = []
        var pauses = 0, resumes = 0, stops = 0
        func play(url: URL, volume: Float) { played.append(url) }
        func pause() { pauses += 1 }
        func resume() { resumes += 1 }
        func stop() { stops += 1 }
    }

    private var player: SpyVoicePlayer!
    private var vm: ActiveWalkViewModel!
    private var recordingURL: URL!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func way(id: String = "walk:test") -> Way {
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let voice = WayMoment(id: "voice-1", frac: 0.3, at: WayCoordinate(lat: 0, lon: 300 / 111_320),
                              kind: .voice(endFrac: 0.35, duration: 20, kind: .spoken, media: .recording(relativePath: "Recordings/honor-test.m4a")))
        let sit = WayMoment(id: "sit-1", frac: 0.5, at: WayCoordinate(lat: 0, lon: 500 / 111_320),
                            kind: .meditation(minutes: 7, isEstimate: false))
        return Way(id: id, source: .ownWalk(UUID()), title: "Test way", departedAt: start, tzIdentifier: nil,
                   expires: nil, route: route, totalDistanceMeters: 1000, theirActiveSeconds: 600,
                   moments: [voice, sit], weather: nil)
    }

    private func makeVM() -> ActiveWalkViewModel {
        var senses = HonorSenses()
        senses.makeVoicePlayer = { [player] in player! }
        senses.isAppActive = { false }
        let vm = ActiveWalkViewModel(mode: .honor, way: way(), honorSenses: senses)
        settleCombineSchedulers()
        return vm
    }

    override func setUpWithError() throws {
        // The engine only queues voices when both the honor toggle and the
        // master Sounds switch are on; a sibling suite may have left either
        // off in the shared defaults.
        UserPreferences.honorVoicesEnabled.value = true
        UserPreferences.soundsEnabled.value = true
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = docs.appendingPathComponent("Recordings/honor-test.m4a")
        try FileManager.default.createDirectory(at: recordingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try TestAudioFile.writeSilentAudioFile(to: recordingURL)
        player = SpyVoicePlayer()
        vm = makeVM()
    }

    override func tearDown() {
        vm.cancel()
        vm = nil
        try? FileManager.default.removeItem(at: recordingURL)
        UserPreferences.honorVoicesEnabled.delete()
        UserPreferences.honorSoftTapEnabled.delete()
        UserPreferences.soundsEnabled.delete()
        super.tearDown()
    }

    private func fix(lon: Double, seconds: Double) -> TempRouteDataSample {
        TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(seconds), latitude: 0, longitude: lon,
                            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1.4, direction: 90)
    }

    /// Every engine stream hops through `receive(on: .main)`: settle after each write.
    private func drive(_ sample: TempRouteDataSample) {
        vm.currentLocation = sample
        settleCombineSchedulers()
    }

    /// The builder refuses `.recording` straight from `.waiting`; in the app
    /// the components report readiness first, and on the simulator none ever
    /// does. Without the real `.recording` status the engine's pause gate
    /// would stay shut and no voice could start.
    private func begin(startedSecondsAgo: TimeInterval = 0) {
        vm.builder.setStatus(.ready)
        if startedSecondsAgo > 0 {
            vm.builder._test_setStartDate(Date().addingTimeInterval(-startedSecondsAgo))
        }
        vm.startRecording()
        settleCombineSchedulers()
    }

    private func recordedEvents() throws -> [TempWalkEvent] {
        try awaitPublisher(vm.builder.workoutEventsPublisher)
    }

    func testEngineBootsOnRecordingStartAndWritesTheMarkerEvent() throws {
        begin()
        XCTAssertNotNil(vm.honorEngine)
        XCTAssertTrue(try recordedEvents().contains { $0.eventType == .honorMode })
    }

    func testVoicePlaysWhereItWasSpokenAndSitOffersACard() {
        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        XCTAssertEqual(player.played, [recordingURL])
        XCTAssertEqual(vm.activeVoice?.id, "voice-1")
        XCTAssertEqual(vm.heardVoiceIDs, ["voice-1"])
        drive(fix(lon: 500 / 111_320, seconds: 400))
        XCTAssertEqual(vm.honorCards.first?.id, "sit-1")
        vm.dismissTopCard()
        XCTAssertTrue(vm.honorCards.isEmpty)
    }

    func testMeditationPausesTheVoiceAndResumesAfter() {
        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        vm.startMeditation(minutes: 7)
        settleCombineSchedulers()
        XCTAssertEqual(player.pauses, 1)
        XCTAssertTrue(vm.isVoicePaused)
        XCTAssertEqual(vm.suggestedMeditationMinutes, 7)
        vm.endMeditationSilently()
        settleCombineSchedulers()
        XCTAssertEqual(player.resumes, 1)
        XCTAssertFalse(vm.isVoicePaused)
        XCTAssertNil(vm.suggestedMeditationMinutes)
    }

    func testTogglePlaybackAndSkip() {
        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        let voice = vm.activeVoice!
        vm.togglePlayback(of: voice)
        XCTAssertEqual(player.pauses, 1)
        XCTAssertTrue(vm.isVoicePaused)
        vm.togglePlayback(of: voice)
        XCTAssertEqual(player.resumes, 1)
        vm.skipVoice()
        XCTAssertGreaterThanOrEqual(player.stops, 1)
        XCTAssertNil(vm.activeVoice)
    }

    func testMissingRecordingFileIsNeitherPlayedNorHeard() throws {
        try FileManager.default.removeItem(at: recordingURL)
        vm.cancel()
        vm = makeVM()
        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        XCTAssertTrue(player.played.isEmpty)
        XCTAssertTrue(vm.heardVoiceIDs.isEmpty)
    }

    func testArrivalWritesEventWaypointAndTheCompanionDelta() throws {
        // Seeding the walk's own start date 500 s back makes the one-second
        // duration timer agree with the engine's clock, so a tick landing
        // mid-test can't move the companion delta.
        begin(startedSecondsAgo: 500)
        vm.honorEngine?.updateActiveDuration(500)
        for i in 0...10 { drive(fix(lon: Double(i) * 0.000898, seconds: Double(i) * 60)) }
        for i in 0..<3 { drive(fix(lon: 10 * 0.000898, seconds: 700 + Double(i))) }
        XCTAssertTrue(try recordedEvents().contains { $0.eventType == .honorArrival })
        XCTAssertEqual(vm.waypoints.filter(HonorPersistence.isArrivalWaypoint).count, 1)
        XCTAssertEqual(vm.waypoints.first?.label, HonorPersistence.arrivalWaypointLabel(wayTitle: "Test way"))
        XCTAssertEqual(vm.honorArrival?.theirSeconds ?? 0, 600, accuracy: 1)
        XCTAssertEqual(vm.honorArrival?.yourSeconds ?? 0, 500, accuracy: 1)
    }

    func testStopTearsDownThePlayer() {
        begin()
        vm.stop()
        XCTAssertGreaterThanOrEqual(player.stops, 1)
        XCTAssertNil(vm.honorEngine)
    }

    func testNaturalFinishClearsTheVoiceAndAdvancesTheQueue() {
        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        XCTAssertNotNil(vm.activeVoice)

        let onFinished = player.onFinished
        onFinished?()
        settleCombineSchedulers()
        XCTAssertNil(vm.activeVoice)
        XCTAssertFalse(vm.isVoicePaused)

        vm.stop()
        XCTAssertNil(vm.honorEngine)

        // Re-boot a live second engine on the same view model. `stop()` left
        // `mode`/`way` untouched and `honorEngine` nil, so the guard on
        // `startHonorEngineIfNeeded()` passes; `resume()` puts the builder
        // back in `.recording` (valid from `.ready`) so the new engine's
        // pause gate isn't shut before it can start a voice.
        vm.resume()
        vm.startHonorEngineIfNeeded()
        settleCombineSchedulers()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        XCTAssertEqual(vm.activeVoice?.id, "voice-1")

        // The closure closed over the FIRST engine's honor generation;
        // firing it now that a second, live engine owns `activeVoice` must
        // be inert, not clear the second engine's voice.
        onFinished?()
        XCTAssertEqual(vm.activeVoice?.id, "voice-1")
        XCTAssertFalse(vm.isVoicePaused)
    }

    func testReplyHereMapsTheNextRecordingToTheOriginVoice() throws {
        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WayStore(baseDirectory: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let testWay = way(id: "walk:\(UUID().uuidString)")
        try store.save(testWay)

        var senses = HonorSenses()
        senses.makeVoicePlayer = { [player] in player! }
        senses.isAppActive = { false }
        senses.store = { store }
        vm.cancel()
        vm = ActiveWalkViewModel(mode: .honor, way: testWay, honorSenses: senses)
        settleCombineSchedulers()

        let voice = testWay.moments.first { $0.id == "voice-1" }!

        // Before the walk starts, `VoiceRecordingManagement.startRecording()`
        // bails on its own `isWalkActive` guard regardless of the test
        // host's microphone authorization — a deterministic way to drive
        // the "never opens" path without depending on that authorization
        // state (this test host, unlike the brief's assumption, does grant
        // the recorder real mic access once a walk is active — see below).
        vm.replyHere(to: voice)
        XCTAssertFalse(vm.voiceRecordingManagement.isRecording)
        XCTAssertNil(vm.pendingReplyOrigin)

        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 300 / 111_320, seconds: 200))
        XCTAssertEqual(vm.activeVoice?.id, "voice-1")

        // Unlike the pre-walk attempt above, the recorder really does open
        // now that the walk is active in this test host.
        vm.replyHere(to: voice)
        XCTAssertNotNil(vm.pendingReplyOrigin)
        if vm.voiceRecordingManagement.isRecording {
            vm.toggleVoiceRecording()
            settleCombineSchedulers()
        }

        // This test host's recorder does open successfully once the walk is
        // active, so exercising the mapping through a real record → stop →
        // AVAudioRecorderDelegate → commit round trip would make this
        // test's timing depend on AVFoundation's asynchronous finish
        // callback. `recordReplyIfPending` — the exact call
        // `bindCompletedRecordings` makes once a real recording completes —
        // is called directly instead, keeping the test deterministic.
        vm.pendingReplyOrigin = vm.activeVoice
        let recording = TempVoiceRecording(uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(5),
                                           duration: 5, fileRelativePath: "Recordings/reply.m4a", isEnhanced: false)
        vm.recordReplyIfPending(latestRecording: recording)
        XCTAssertEqual(store.replies(for: testWay.id), [1: "Recordings/reply.m4a"])
        XCTAssertNil(vm.pendingReplyOrigin)
    }

    func testShowCardJumpsTheQueue() {
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let first = WayMoment(id: "wp-1", frac: 0.2, at: WayCoordinate(lat: 0, lon: 200 / 111_320),
                              kind: .waypoint(label: "First", icon: "star"))
        let second = WayMoment(id: "wp-2", frac: 0.4, at: WayCoordinate(lat: 0, lon: 400 / 111_320),
                               kind: .waypoint(label: "Second", icon: "star"))
        let testWay = Way(id: "walk:test", source: .ownWalk(UUID()), title: "Two-card way", departedAt: start,
                          tzIdentifier: nil, expires: nil, route: route, totalDistanceMeters: 1000,
                          theirActiveSeconds: 600, moments: [first, second], weather: nil)
        var senses = HonorSenses()
        senses.makeVoicePlayer = { [player] in player! }
        senses.isAppActive = { false }
        vm.cancel()
        vm = ActiveWalkViewModel(mode: .honor, way: testWay, honorSenses: senses)
        settleCombineSchedulers()

        begin()
        drive(fix(lon: 0, seconds: 0))
        drive(fix(lon: 200 / 111_320, seconds: 100))
        drive(fix(lon: 400 / 111_320, seconds: 200))

        XCTAssertEqual(vm.honorCards.map(\.id), ["wp-1", "wp-2"])
        vm.showCard(for: second)
        XCTAssertEqual(vm.honorCards.map(\.id), ["wp-2", "wp-1"])
    }

    func testArrivalCardCountsHeardVoicesAndReachedPlaces() throws {
        // A `.rest` moment sitting 1 km off the route the walker passes
        // `frac`-wise but never comes within the 60 m moment radius: it must
        // never fire `.momentReached`, so `placesPassed` must stay 1 (just
        // "sit-1"). `way.moments.count - voiceCount` would count it anyway
        // and give 2 — that's the bug this fixture is built to catch.
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let voice = WayMoment(id: "voice-1", frac: 0.3, at: WayCoordinate(lat: 0, lon: 300 / 111_320),
                              kind: .voice(endFrac: 0.35, duration: 20, kind: .spoken, media: .recording(relativePath: "Recordings/honor-test.m4a")))
        let sit = WayMoment(id: "sit-1", frac: 0.5, at: WayCoordinate(lat: 0, lon: 500 / 111_320),
                            kind: .meditation(minutes: 7, isEstimate: false))
        let unreachedRest = WayMoment(id: "rest-1", frac: 0.7, at: WayCoordinate(lat: 0.009, lon: 700 / 111_320),
                                      kind: .rest(minutes: 3))
        let testWay = Way(id: "walk:test", source: .ownWalk(UUID()), title: "Test way", departedAt: start,
                          tzIdentifier: nil, expires: nil, route: route, totalDistanceMeters: 1000,
                          theirActiveSeconds: 600, moments: [voice, sit, unreachedRest], weather: nil)

        var senses = HonorSenses()
        senses.makeVoicePlayer = { [player] in player! }
        senses.isAppActive = { false }
        vm.cancel()
        vm = ActiveWalkViewModel(mode: .honor, way: testWay, honorSenses: senses)
        settleCombineSchedulers()

        begin(startedSecondsAgo: 500)
        vm.honorEngine?.updateActiveDuration(500)
        for i in 0...10 { drive(fix(lon: Double(i) * 0.000898, seconds: Double(i) * 60)) }
        for i in 0..<3 { drive(fix(lon: 10 * 0.000898, seconds: 700 + Double(i))) }
        XCTAssertEqual(vm.honorArrival?.voicesHeard, 1)
        XCTAssertEqual(vm.honorArrival?.placesPassed, 1)
    }

    func testMediaURLForWayFileResolvesInsideTheStoreAndRejectsTraversal() throws {
        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WayStore(baseDirectory: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let testWay = way(id: "walk:\(UUID().uuidString)")
        try store.save(testWay)

        var senses = HonorSenses()
        senses.makeVoicePlayer = { [player] in player! }
        senses.isAppActive = { false }
        senses.store = { store }
        vm.cancel()
        vm = ActiveWalkViewModel(mode: .honor, way: testWay, honorSenses: senses)
        settleCombineSchedulers()

        let mediaFile = store.mediaURL(for: testWay.id, relative: "audio/1.m4a")
        try FileManager.default.createDirectory(at: mediaFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try TestAudioFile.writeSilentAudioFile(to: mediaFile)

        // The traversal targets must actually exist on disk before the
        // assertions run: `resolvedMediaURL` returns nil both when the
        // containment check rejects a path AND when the (contained) file is
        // simply missing, so an escape target with nothing there would read
        // as "rejected" even if the containment check were deleted outright.
        // `.file("../../escape.m4a")` resolves to `mediaDirectory/../..` =
        // the store's own base directory.
        let escapedStoreFile = storeDir.appendingPathComponent("escape.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: escapedStoreFile.path, contents: Data()))
        // `.recording(relativePath: "../Library/escape.m4a")` resolves to
        // Documents' sibling `Library/` — writable in the simulator, unlike
        // the container root a bare "../escape.m4a" would land in.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let escapedLibraryFile = docs.deletingLastPathComponent().appendingPathComponent("Library/escape.m4a")
        try FileManager.default.createDirectory(at: escapedLibraryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: escapedLibraryFile.path, contents: Data()))
        defer {
            try? FileManager.default.removeItem(at: escapedStoreFile)
            try? FileManager.default.removeItem(at: escapedLibraryFile)
        }

        XCTAssertNotNil(vm.mediaURL(for: .file("audio/1.m4a")))
        XCTAssertNil(vm.mediaURL(for: .file("../../escape.m4a")))
        XCTAssertNil(vm.mediaURL(for: .recording(relativePath: "../Library/escape.m4a")))
    }
}
