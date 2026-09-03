import XCTest
@testable import Pilgrim

final class OwnWalkWayBuilderTests: XCTestCase {

    private let start = DateFactory.makeDate(2026, 5, 1, 8, 0, 0)
    private var recordingURL: URL!

    override func setUpWithError() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = docs.appendingPathComponent("Recordings/a/b.m4a")
        try FileManager.default.createDirectory(at: recordingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try TestAudioFile.writeSilentAudioFile(to: recordingURL)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: recordingURL) }

    private func sample(_ i: Int, lon: Double) -> TempRouteDataSample {
        TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(Double(i) * 60),
                            latitude: 42.88, longitude: lon, altitude: 300,
                            horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1.4, direction: 90)
    }

    /// Ten samples 100 m apart, one per minute.
    private func walk(uuid: UUID = UUID()) -> TempWalk {
        let route = (0..<10).map { sample($0, lon: -8.54 + Double($0) * 0.00122) }
        let recording = TempVoiceRecording(
            uuid: nil, startDate: start.addingTimeInterval(4 * 60 + 10),
            endDate: start.addingTimeInterval(5 * 60), duration: 50,
            fileRelativePath: "Recordings/a/b.m4a",
            transcription: "a thought that runs on for more than eight words in total")
        let sitting = TempActivityInterval(
            uuid: nil, activityType: .meditation,
            startDate: start.addingTimeInterval(7 * 60), endDate: start.addingTimeInterval(19 * 60))
        let pin = TempWaypoint(uuid: nil, latitude: 42.88, longitude: -8.54 + 2 * 0.00122,
                               label: "Oak", icon: "leaf", timestamp: start.addingTimeInterval(120))
        let arrival = TempWaypoint(uuid: nil, latitude: 42.88, longitude: -8.54,
                                   label: "x", icon: SeekPersistence.arrivalWaypointIcon, timestamp: start)
        let pause = TempWalkPause(uuid: nil, startDate: start.addingTimeInterval(3 * 60),
                                  endDate: start.addingTimeInterval(3 * 60 + 200), pauseType: .manual)
        return WalkDataFactory.makeWalk(
            uuid: uuid, startDate: start, endDate: start.addingTimeInterval(9 * 60),
            activeDuration: 540 - 200, routeData: route, pauses: [pause],
            voiceRecordings: [recording], activityIntervals: [sitting],
            waypoints: [pin, arrival])
    }

    func testBuildsMomentsAtTheRightFracsWithCoordinates() throws {
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk()))
        XCTAssertEqual(way.route.count, 10)
        XCTAssertEqual(way.totalDistanceMeters, 900, accuracy: 10)
        XCTAssertEqual(way.theirActiveSeconds, 340)

        let voice = try XCTUnwrap(way.moments.first { $0.id == "voice-1" })
        XCTAssertEqual(voice.frac, 4.0 / 9.0, accuracy: 0.03)
        XCTAssertEqual(voice.at?.lon ?? 0, -8.54 + 4 * 0.00122, accuracy: 0.0001)
        guard case .voice(_, let duration, let kind, let media) = voice.kind else { return XCTFail("kind") }
        XCTAssertEqual(duration, 50)
        XCTAssertEqual(kind, .spoken)
        XCTAssertEqual(media, .recording(relativePath: "Recordings/a/b.m4a"))

        let sit = try XCTUnwrap(way.moments.first { $0.id == "sit-1" })
        guard case .meditation(let minutes, let isEstimate) = sit.kind else { return XCTFail("kind") }
        XCTAssertEqual(minutes, 12)
        XCTAssertFalse(isEstimate)

        let rest = try XCTUnwrap(way.moments.first { $0.id == "rest-1" })
        guard case .rest(let restMinutes) = rest.kind else { return XCTFail("kind") }
        XCTAssertEqual(restMinutes, 3)

        XCTAssertTrue(way.moments.contains { $0.id == "waypoint-1" })
        XCTAssertEqual(way.moments.filter { if case .waypoint = $0.kind { return true }; return false }.count, 1,
                       "reserved-icon waypoints are excluded")
        XCTAssertEqual(way.moments.map(\.frac), way.moments.map(\.frac).sorted())
    }

    func testNilWithoutARoute() {
        XCTAssertNil(OwnWalkWayBuilder.make(from: WalkDataFactory.makeWalk(routeData: [])))
    }

    /// A walk that never left one spot is jitter, not a Way: every frac would
    /// collapse onto the same place and the companion could not move.
    func testNilWhenTheRouteIsShorterThanTheFloor() {
        let jitter = (0..<10).map { sample($0, lon: -8.54 + Double($0) * 0.00001) }  // ~8 m end to end
        XCTAssertNil(OwnWalkWayBuilder.make(from: WalkDataFactory.makeWalk(uuid: UUID(), startDate: start, routeData: jitter)))
    }

    func testAWayJustOverTheFloorIsStillBuilt() throws {
        let short = (0..<10).map { sample($0, lon: -8.54 + Double($0) * 0.00005) }   // ~40 m end to end
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: WalkDataFactory.makeWalk(uuid: UUID(), startDate: start, routeData: short)))
        XCTAssertGreaterThanOrEqual(way.totalDistanceMeters, OwnWalkWayBuilder.minLengthMeters)
    }

    func testSkipsRecordingsWhoseFileIsGone() throws {
        try FileManager.default.removeItem(at: recordingURL)
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk()))
        XCTAssertFalse(way.moments.contains { $0.isVoice })
        XCTAssertEqual(way.voiceCount, 0)
    }

    func testIdentityAndTitle() throws {
        let id = UUID()
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk(uuid: id)))
        XCTAssertEqual(way.id, "walk:\(id.uuidString)")
        XCTAssertEqual(way.source, .ownWalk(id))
        XCTAssertNil(way.expires)
    }
}

extension OwnWalkWayBuilderTests {

    func testSpansFollowTheRecordingAndTheSitting() throws {
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk()))
        let spans = try XCTUnwrap(way.spans)
        XCTAssertEqual(spans.map(\.kind), [.talking, .meditating])
        for span in spans {
            XCTAssertGreaterThan(span.endFrac, span.startFrac)
            XCTAssertGreaterThanOrEqual(span.startFrac, 0)
            XCTAssertLessThanOrEqual(span.endFrac, 1)
        }
    }
}

extension OwnWalkWayBuilderTests {

    func testTheWalkersOwnTranscriptionRidesOntoTheVoiceMoment() throws {
        let way = try XCTUnwrap(OwnWalkWayBuilder.make(from: walk()))
        let voice = try XCTUnwrap(way.moments.first { $0.isVoice })
        XCTAssertEqual(voice.transcript, "a thought that runs on for more than eight words in total")
    }
}
