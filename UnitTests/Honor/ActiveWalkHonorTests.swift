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

    private func way() -> Way {
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let voice = WayMoment(id: "voice-1", frac: 0.3, at: WayCoordinate(lat: 0, lon: 300 / 111_320),
                              kind: .voice(endFrac: 0.35, duration: 20, kind: .spoken, media: .recording(relativePath: "Recordings/honor-test.m4a")))
        let sit = WayMoment(id: "sit-1", frac: 0.5, at: WayCoordinate(lat: 0, lon: 500 / 111_320),
                            kind: .meditation(minutes: 7, isEstimate: false))
        return Way(id: "walk:test", source: .ownWalk(UUID()), title: "Test way", departedAt: start, tzIdentifier: nil,
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
}
