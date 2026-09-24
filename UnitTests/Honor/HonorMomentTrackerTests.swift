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

    func testPausedVoiceIsDroppedWhenTheWalkerMovesOnAndTheNextStartsLater() {
        var t = tracker()
        _ = t.update(location: coord(300), progressFrac: 0.3, gates: .init(), isStationary: false)   // voice 1 plays
        XCTAssertEqual(t.gatesDidChange(.init(meditating: true)), [.voicePause])
        _ = t.update(location: coord(500), progressFrac: 0.5, gates: .init(meditating: true), isStationary: false)   // voice 2 waits
        // Standing still 320 m past voice 1: the paused voice is exempt from the drop.
        XCTAssertEqual(t.update(location: coord(620), progressFrac: 0.62, gates: .init(meditating: true), isStationary: true), [])
        XCTAssertTrue(t.isVoicePaused)
        // Moving on: voice 1 is dropped; voice 2 (130 m back) keeps waiting for the gate.
        XCTAssertEqual(t.update(location: coord(630), progressFrac: 0.63, gates: .init(meditating: true), isStationary: false),
                       [.voiceDropped(voice1)])
        XCTAssertNil(t.playing)
        XCTAssertFalse(t.isVoicePaused)
        XCTAssertEqual(t.gatesDidChange(.init()), [.voiceStart(voice2)])
    }

    func testMomentWithoutCoordinateFallsBackToItsFrac() {
        let rest = WayMoment(id: "rest-1", frac: 0.4, at: nil, kind: .rest(minutes: 3))
        var t = HonorMomentTracker(moments: [rest], geometry: geometry, voicesEnabled: true)
        XCTAssertEqual(t.update(location: coord(330), progressFrac: 0.4, gates: .init(), isStationary: false), [], "70 m short of the frac's place")
        XCTAssertEqual(t.update(location: coord(400), progressFrac: 0.4, gates: .init(), isStationary: false), [.reached(rest)])
    }

    func testFracToleranceIsFivePercent() {
        var t = HonorMomentTracker(moments: [sit1], geometry: geometry, voicesEnabled: true)
        XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.24, gates: .init(), isStationary: false), [])
        XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.26, gates: .init(), isStationary: false), [.reached(sit1)])
    }

    func testEveryGateHoldsAVoice() {
        let closed: [HonorMomentTracker.Gates] = [
            .init(paused: true), .init(meditating: true), .init(recording: true), .init(externalAudio: true)
        ]
        for gates in closed {
            var t = HonorMomentTracker(moments: [voice1], geometry: geometry, voicesEnabled: true)
            XCTAssertEqual(t.update(location: coord(300), progressFrac: 0.3, gates: gates, isStationary: false), [], "\(gates)")
            XCTAssertEqual(t.gatesDidChange(.init()), [.voiceStart(voice1)], "\(gates)")
        }
    }
}

extension HonorMomentTrackerTests {

    private func water(_ id: String, frac: Double, offLine: Double = 10) -> WayMark {
        WayMark(id: id, kind: .water, name: "Fuente \(id)",
                at: WayCoordinate(lat: 0, lon: frac * 1000 / 111_320), frac: frac, offLineMeters: offLine)
    }

    private func markTracker(_ marks: [WayMark]) -> HonorMomentTracker {
        HonorMomentTracker(moments: [], marks: marks, geometry: geometry, voicesEnabled: false)
    }

    private func markAhead(_ actions: [HonorMomentTracker.Action]) -> [String] {
        actions.compactMap { if case .markAhead(let mark, _) = $0 { return mark.id } else { return nil } }
    }

    func testWaterFiresOnceInsideThreeHundredMetresBeforeIt() {
        var t = markTracker([water("a", frac: 0.5)])
        // 400 m short: too early.
        XCTAssertEqual(markAhead(t.update(location: coord(100), progressFrac: 0.1, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [])
        // 250 m short: the caption.
        let hit = t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                           isStationary: false, activeSeconds: 60, isOnWay: true)
        XCTAssertEqual(markAhead(hit), ["a"])
        guard case .markAhead(_, let meters) = hit.first else { return XCTFail("action") }
        XCTAssertEqual(meters, 250, accuracy: 5)
        // And never again — not inside the quiet hour, and not after it
        // either while the mark is still ahead.
        XCTAssertEqual(markAhead(t.update(location: coord(300), progressFrac: 0.3, gates: .init(),
                                          isStationary: false, activeSeconds: 120, isOnWay: true)), [])
        XCTAssertEqual(markAhead(t.update(location: coord(300), progressFrac: 0.3, gates: .init(),
                                          isStationary: false, activeSeconds: 4000, isOnWay: true)), [],
                       "a mark that has spoken stays silent even once the hour has passed")
    }

    func testWaterNeverFiresOnceItIsBehindYou() {
        var t = markTracker([water("a", frac: 0.5)])
        XCTAssertEqual(markAhead(t.update(location: coord(600), progressFrac: 0.6, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [],
                       "a fountain you have already passed is not news")
    }

    func testAFountainOffTheTrailIsADetourNotADrink() {
        var t = markTracker([water("far", frac: 0.5, offLine: 250)])
        XCTAssertEqual(markAhead(t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }

    func testOffWayWalkersGetNothing() {
        var t = markTracker([water("a", frac: 0.5)])
        XCTAssertEqual(markAhead(t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: false)), [])
    }

    func testTheFirstIsFreeThenOnePerHourOfWalking() {
        var t = markTracker([water("a", frac: 0.3), water("b", frac: 0.5), water("c", frac: 0.9)])
        XCTAssertEqual(markAhead(t.update(location: coord(100), progressFrac: 0.1, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), ["a"])
        // b is 200 m ahead, 20 minutes later: inside the quiet hour.
        XCTAssertEqual(markAhead(t.update(location: coord(300), progressFrac: 0.3, gates: .init(),
                                          isStationary: false, activeSeconds: 1200, isOnWay: true)), [],
                       "a skipped mark stays a silent pin")
        // c is 200 m ahead, an hour and a half in.
        XCTAssertEqual(markAhead(t.update(location: coord(700), progressFrac: 0.7, gates: .init(),
                                          isStationary: false, activeSeconds: 5400, isOnWay: true)), ["c"])
    }

    func testOnlyWaterSpeaks() {
        let bed = WayMark(id: "bed", kind: .bed, name: "Albergue",
                          at: WayCoordinate(lat: 0, lon: 500 / 111_320), frac: 0.5, offLineMeters: 10)
        var t = markTracker([bed])
        XCTAssertEqual(markAhead(t.update(location: coord(250), progressFrac: 0.25, gates: .init(),
                                          isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }
}

/// The stamp office notice: on the Shikoku henro the nōkyōjo shuts at 17:00,
/// and a walker who arrives after it walks back for the stamp another day.
/// A fact and never a forecast — what the office does and how far it is.
extension HonorMomentTrackerTests {

    /// 10 km straight east, so a frac is a kilometre: the stamp rule works in
    /// kilometres where the water rule works in metres.
    private var longGeometry: WayGeometry {
        WayGeometry(route: (0...10).map { i in
            WayPoint(lat: 0, lon: Double(i) * 0.00898, alt: nil, t: Double(i) * 600)
        })
    }

    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// A fixed wall clock in the temple's own time zone.
    private static func tokyoClock(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: hour, minute: minute))!
    }

    private func office(_ hour: Int, _ minute: Int) -> HonorMomentTracker.StampOffice {
        HonorMomentTracker.StampOffice(closesMinutes: 17 * 60, timeZone: Self.tokyo,
                                       now: { Self.tokyoClock(hour, minute) })
    }

    /// A numbered fudasho as the dataset writes one: the number lives in the
    /// composed `text`, the romanized name in `label`.
    private func temple(_ number: Int, frac: Double) -> WayMoment {
        var moment = WayMoment(id: "temple-\(number)", frac: frac,
                               at: WayCoordinate(lat: 0, lon: frac * 10_000 / 111_320),
                               kind: .waypoint(label: "Kirihata-ji", icon: "seal"))
        moment.text = "Temple \(number) · Koyasan Shingon · stamp available (¥500)"
        return moment
    }

    private func stampTracker(_ moments: [WayMoment], marks: [WayMark] = [],
                              at clock: (hour: Int, minute: Int)? = (15, 30)) -> HonorMomentTracker {
        HonorMomentTracker(moments: moments, marks: marks, geometry: longGeometry, voicesEnabled: false,
                           stamp: clock.map { office($0.hour, $0.minute) })
    }

    private func stampAhead(_ actions: [HonorMomentTracker.Action]) -> [String] {
        actions.compactMap { if case .stampAhead(let temple, _) = $0 { return temple.id } else { return nil } }
    }

    /// Every route but Shikoku's. Nothing, ever — whatever the hour.
    func testARouteThatStatesNoStampHoursNeverSpeaksOfTemples() {
        var t = stampTracker([temple(10, frac: 0.5)], at: nil)
        XCTAssertEqual(stampAhead(t.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                           isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }

    func testTheNoticeOpensTwoHoursBeforeClosingAndShutsWithTheOffice() {
        // 14:59: the afternoon is still young and the notice is noise.
        var early = stampTracker([temple(10, frac: 0.5)], at: (14, 59))
        XCTAssertEqual(stampAhead(early.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                               isStationary: false, activeSeconds: 0, isOnWay: true)), [])
        // 15:00 exactly: two hours to closing.
        var onTheHour = stampTracker([temple(10, frac: 0.5)], at: (15, 0))
        XCTAssertEqual(stampAhead(onTheHour.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                                   isStationary: false, activeSeconds: 0, isOnWay: true)),
                       ["temple-10"])
        // 17:00: there is no stamp left to be had, and a walker who has lost
        // it does not need telling.
        var closed = stampTracker([temple(10, frac: 0.5)], at: (17, 0))
        XCTAssertEqual(stampAhead(closed.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                                isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }

    func testATempleInsideAKilometreHasStoppedBeingADecision() {
        // Fracs are taken off the line's true length, so the two cases sit a
        // metre either side of the kilometre rather than near it.
        let total = longGeometry.totalMeters
        var near = stampTracker([temple(10, frac: 0.5)])
        XCTAssertEqual(stampAhead(near.update(location: coord(4000), progressFrac: 0.5 - 999 / total,
                                              gates: .init(), isStationary: false,
                                              activeSeconds: 0, isOnWay: true)), [],
                       "999 m short: the walker can see it and is already arriving")

        var far = stampTracker([temple(10, frac: 0.5)])
        let hit = far.update(location: coord(4000), progressFrac: 0.5 - 1001 / total, gates: .init(),
                             isStationary: false, activeSeconds: 0, isOnWay: true)
        XCTAssertEqual(stampAhead(hit), ["temple-10"])
        guard case .stampAhead(_, let meters) = hit.first else { return XCTFail("action") }
        XCTAssertEqual(meters, 1001, accuracy: 1)
    }

    func testEachTempleSpeaksOnce() {
        var t = stampTracker([temple(10, frac: 0.5), temple(11, frac: 0.9)])
        XCTAssertEqual(stampAhead(t.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                           isStationary: false, activeSeconds: 0, isOnWay: true)),
                       ["temple-10"])
        // Still 3 km ahead a minute later: inside the quiet hour, and spoken
        // for in any case.
        XCTAssertEqual(stampAhead(t.update(location: coord(2000), progressFrac: 0.2, gates: .init(),
                                           isStationary: false, activeSeconds: 60, isOnWay: true)), [])
        // An hour and a half of walking on, temple 10 has had its say and it
        // is temple 11 — 4 km ahead — that speaks.
        XCTAssertEqual(stampAhead(t.update(location: coord(5000), progressFrac: 0.5, gates: .init(),
                                           isStationary: false, activeSeconds: 5400, isOnWay: true)),
                       ["temple-11"])
    }

    func testATempleAlreadyBehindIsNeverAnnounced() {
        var t = stampTracker([temple(10, frac: 0.3)])
        XCTAssertEqual(stampAhead(t.update(location: coord(6000), progressFrac: 0.6, gates: .init(),
                                           isStationary: false, activeSeconds: 0, isOnWay: true)), [],
                       "a temple you have walked past cannot still be stamped today")
    }

    /// A seal means a stamp is available, which is equally true of Camino
    /// pilgrim offices and Kumano shrines. Only the numbered fudasho keep an
    /// office that shuts, and only the dataset's own "Temple N" says so.
    func testASealThatIsNotANumberedTempleStaysSilent() {
        var pilgrimOffice = WayMoment(id: "wp-sjpp-pilgrim-office", frac: 0.5,
                                      at: WayCoordinate(lat: 0, lon: 5000 / 111_320),
                                      kind: .waypoint(label: "Pilgrim Welcome Office", icon: "seal"))
        pilgrimOffice.text = "Pilgrim office · 172 m · stamp available"
        var t = stampTracker([pilgrimOffice])
        XCTAssertEqual(stampAhead(t.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                           isStationary: false, activeSeconds: 0, isOnWay: true)), [])
    }

    func testAWalkerOffTheWayIsToldNothing() {
        var t = stampTracker([temple(10, frac: 0.5)])
        XCTAssertEqual(stampAhead(t.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                                           isStationary: false, activeSeconds: 0, isOnWay: false)), [],
                       "off the way the distance ahead would be a guess")
    }

    /// One caption line, one notice: the temple takes it, and the fountain
    /// keeps the quiet hour it would have started anyway.
    func testTheTempleTakesTheLineAheadOfTheFountain() {
        let fountain = WayMark(id: "fuente", kind: .water, name: "Fuente",
                               at: WayCoordinate(lat: 0, lon: 1200 / 111_320), frac: 0.12, offLineMeters: 10)
        var t = stampTracker([temple(10, frac: 0.5)], marks: [fountain])
        let actions = t.update(location: coord(1000), progressFrac: 0.1, gates: .init(),
                               isStationary: false, activeSeconds: 0, isOnWay: true)
        XCTAssertEqual(stampAhead(actions), ["temple-10"])
        XCTAssertEqual(markAhead(actions), [], "the fountain waits out the quiet hour the temple started")
    }
}
