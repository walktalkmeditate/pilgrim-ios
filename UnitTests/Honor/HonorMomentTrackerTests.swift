import XCTest
import CoreLocation
@testable import Pilgrim

final class HonorMomentTrackerTests: XCTestCase {

    /// 1 km straight east; a voice at 300 m, a sitting at 300 m, a second voice at 500 m, a photo at 700 m.
    private let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
    private lazy var geometry = WayGeometry(route: route)
    private func at(_ meters: Double) -> WayCoordinate { WayCoordinate(lat: 0, lon: meters / 111_320) }
    private func coord(_ meters: Double, lat: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: meters / 111_320)
    }
    private lazy var voice1 = WayMoment(id: "voice-1", frac: 0.3, at: at(300),
        kind: .voice(endFrac: 0.35, duration: 40, kind: .spoken, media: .file("audio/1.m4a")))
    private lazy var sit1 = WayMoment(id: "sit-1", frac: 0.3, at: at(300), kind: .meditation(minutes: 12, isEstimate: false))
    private lazy var voice2 = WayMoment(id: "voice-2", frac: 0.5, at: at(500),
        kind: .voice(endFrac: 0.55, duration: 30, kind: .spoken, media: .file("audio/2.m4a")))
    private lazy var photo1 = WayMoment(id: "photo-1", frac: 0.7, at: at(700), kind: .photo(media: .file("photos/1.jpg")))

    private func tracker(voicesEnabled: Bool = true) -> HonorMomentTracker {
        HonorMomentTracker(moments: [voice1, sit1, voice2, photo1], geometry: geometry, voicesEnabled: voicesEnabled)
    }

    func testFiresOnceAndRespectsTheFracGate() {
        var t = tracker()
        // Standing at 300 m but progress says 0.1: too early (a crossing path), nothing fires.
        XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.1, gates: .init(), isStationary: false), [])
        let actions = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(actions, [.reached(sit1), .voiceStart(voice1)])
        XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false), [])
    }

    func testRadiiDifferByKind() {
        var t = tracker()
        // 50 m north of the photo: inside the 60 m card radius.
        XCTAssertEqual(t.update(location: coord(700, lat: 50 / 111_320), progressFrac: 0.7, gates: .init(), isStationary: false),
                       [.reached(photo1)])
        // 50 m north of voice 2: outside the 42 m voice radius.
        XCTAssertEqual(t.update(location: coord(500, lat: 50 / 111_320), progressFrac: 0.5, gates: .init(), isStationary: false), [])
    }

    func testQueueWaitsForThePlayingVoiceThenStartsTheNext() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(t.update(location: coord(500), progressFrac: 0.5, gates: .init(), isStationary: false), [],
                       "voice 2 is queued behind voice 1")
        XCTAssertEqual(t.voiceDidFinish(gates: .init()), [.voiceStart(voice2)])
        XCTAssertEqual(t.voiceDidFinish(gates: .init()), [])
    }

    func testSitPausesThePlayingVoiceAndResumesIt() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(t.gatesDidChange(.init(meditating: true)), [.voicePause])
        XCTAssertTrue(t.isVoicePaused)
        XCTAssertEqual(t.gatesDidChange(.init(meditating: true)), [], "no repeat")
        XCTAssertEqual(t.gatesDidChange(.init()), [.voiceResume])
    }

    func testGatedVoiceWaitsThenStartsWhenTheGateClears() {
        var t = tracker()
        let actions = t.update(location: coord(300), progressFrac: 0.3, gates: .init(recording: true), isStationary: false)
        XCTAssertEqual(actions, [.reached(sit1)])
        XCTAssertEqual(t.gatesDidChange(.init()), [.voiceStart(voice1)])
    }

    func testQueuedVoiceDropsWhenMovingPastButNotWhileStationary() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(recording: true), isStationary: false)
        // 320 m past the spot, standing still: exempt (and 80 m short of the photo, so no card).
        XCTAssertEqual(t.update(location: coord(620), progressFrac: 0.62, gates: .init(recording: true), isStationary: true), [])
        // Moving: dropped.
        XCTAssertEqual(t.update(location: coord(630), progressFrac: 0.63, gates: .init(recording: true), isStationary: false),
                       [.voiceDropped(voice1)])
        XCTAssertEqual(t.gatesDidChange(.init()), [])
    }

    func testQueuedVoiceIsKeptWhileAnotherVoicePlays() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)   // voice 1 plays
        _ = t.update(location: coord(500), progressFrac: 0.5, gates: .init(), isStationary: false)   // voice 2 waits
        // 320 m past voice 2 while voice 1 still plays: nothing is dropped.
        XCTAssertEqual(t.update(location: coord(820), progressFrac: 0.82, gates: .init(), isStationary: false), [])
        XCTAssertEqual(t.voiceDidFinish(gates: .init()), [.voiceStart(voice2)])
    }

    func testVoicesDisabledStillReachesCardsAndNeverStartsAudio() {
        var t = tracker(voicesEnabled: false)
        let actions = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)
        XCTAssertEqual(actions, [.reached(sit1)])
        XCTAssertNil(t.playing)
    }
}
