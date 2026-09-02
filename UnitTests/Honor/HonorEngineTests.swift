import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

final class HonorEngineTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_000_000)

    /// Out and back along the equator: 500 m east (6 points), 500 m west (5 points), 60 s per point.
    private func outAndBackWay() -> Way {
        let out = (0...5).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        let back = (1...5).map { i in WayPoint(lat: 0, lon: Double(5 - i) * 0.000898, alt: nil, t: Double(5 + i) * 60) }
        return Way(id: "walk:test", source: .ownWalk(UUID()), title: "loop", departedAt: clock,
                   tzIdentifier: nil, expires: nil, route: out + back,
                   totalDistanceMeters: 1000, theirActiveSeconds: 600, moments: [], weather: nil)
    }

    /// A straight kilometre east along the equator, eleven points, 60 s apart.
    private func straightWay() -> Way {
        let route = (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
        return Way(id: "walk:straight", source: .ownWalk(UUID()), title: "line", departedAt: clock,
                   tzIdentifier: nil, expires: nil, route: route,
                   totalDistanceMeters: 1000, theirActiveSeconds: 600, moments: [], weather: nil)
    }

    private func fix(lon: Double, lat: Double = 0, accuracy: Double = 5, speed: Double = 1.4, at seconds: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, course: 90, speed: speed,
                   timestamp: clock.addingTimeInterval(seconds))
    }

    private func makeEngine(way: Way? = nil) -> HonorEngine {
        HonorEngine(way: way ?? outAndBackWay(), softTapEnabled: true, voicesEnabled: true, now: { self.clock })
    }

    func testAnchorsAtLowestFracAndFollowsTheOutboundLeg() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.000898 * 0.5, at: 0))
        XCTAssertEqual(engine.startFrac ?? -1, 0.05, accuracy: 0.01, "lowest frac within 60 m, not the return leg")
        XCTAssertTrue(engine.isOnWay)
        // Walk out to 250 m: both legs share this pavement; progress must read 0.25, never 0.75.
        engine.processLocation(fix(lon: 0.000898 * 2.5, at: 120))
        XCTAssertEqual(engine.progressFrac, 0.25, accuracy: 0.02)
        XCTAssertEqual(engine.distanceRemainingMeters, 750, accuracy: 30)
    }

    func testFarFromTheWayAnchorsAtZeroAndIsOffWay() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.05, lat: 0.05, at: 0))
        XCTAssertEqual(engine.startFrac, 0)
        XCTAssertFalse(engine.isOnWay)
        XCTAssertGreaterThan(engine.offWayMeters, 1000)
    }

    func testCompanionRunsOnActiveDurationFromTheAnchor() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.000898 * 2, at: 0))     // 200 m in → their t = 120 s
        XCTAssertEqual(engine.companionT0, 120, accuracy: 2)
        engine.updateActiveDuration(60)
        XCTAssertEqual(engine.companionFrac, 0.30, accuracy: 0.02)
        engine.updateActiveDuration(1200)
        XCTAssertEqual(engine.companionFrac, 1)
    }

    func testArrivalNeedsProgressAndDistanceNotJustProximity() {
        let engine = makeEngine()
        var arrived: [HonorEngineEvent] = []
        let sub = engine.events.sink { if case .arrived = $0 { arrived.append($0) } }
        defer { sub.cancel() }
        // Standing at the start, which is also the end: three fixes must NOT arrive.
        for i in 0..<3 { engine.processLocation(fix(lon: 0, at: Double(i))) }
        XCTAssertTrue(arrived.isEmpty)
        XCTAssertEqual(engine.phase, .walking)
        // Walk the whole loop.
        for i in 1...5 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        for i in 1...4 { engine.processLocation(fix(lon: 0.000898 * Double(5 - i), at: Double(5 + i) * 60)) }
        engine.updateActiveDuration(540)
        for i in 0..<3 { engine.processLocation(fix(lon: 0.00001, at: 600 + Double(i))) }
        XCTAssertEqual(engine.phase, .arrived)
        guard case .arrived(let theirs, let yours) = arrived.first else { return XCTFail("no arrival") }
        XCTAssertEqual(theirs, 600, accuracy: 1)
        XCTAssertEqual(yours, 540)
    }

    func testSoftTapFiresOnceAfterSustainedDriftAndRearms() {
        let engine = makeEngine()
        var taps = 0
        let sub = engine.events.sink { if case .softTap = $0 { taps += 1 } }
        defer { sub.cancel() }
        engine.processLocation(fix(lon: 0.000898, at: 0))
        // 400 m north of the line, for 3 minutes.
        for s in stride(from: 10.0, through: 180, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: s))
        }
        XCTAssertEqual(taps, 1)
        clock = Date(timeIntervalSince1970: 1_000_000 + 190)
        engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: 190))
        XCTAssertEqual(taps, 1, "no repeat while still off")
        clock = Date(timeIntervalSince1970: 1_000_000 + 200)
        engine.processLocation(fix(lon: 0.000898, at: 200))
        for s in stride(from: 210.0, through: 340, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: s))
        }
        XCTAssertEqual(taps, 2, "re-armed after returning within 60 m")
    }

    func testLowestFracFromRespectsTheFloor() {
        let geo = WayGeometry(route: outAndBackWay().route)
        let probe = CLLocationCoordinate2D(latitude: 0, longitude: 0.000898 * 2.5)
        XCTAssertEqual(geo.lowestFrac(within: 60, of: probe) ?? -1, 0.25, accuracy: 0.01)
        XCTAssertEqual(geo.lowestFrac(within: 60, of: probe, from: 0.5) ?? -1, 0.75, accuracy: 0.01)
    }

    func testReacquireOnTheReturnLegNeverFallsBackToTheOutboundLeg() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0, at: 0))
        for i in 1...5 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        for i in 1...2 { engine.processLocation(fix(lon: 0.000898 * Double(5 - i), at: Double(5 + i) * 60)) }
        XCTAssertEqual(engine.progressFrac, 0.7, accuracy: 0.02)
        // Detour 400 m north for over two minutes, then rejoin at the trailhead,
        // which is frac 0 (outbound) and frac 1 (return) at once.
        for s in stride(from: 430.0, through: 560, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898 * 2, lat: 0.0036, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 570)
        engine.processLocation(fix(lon: 0, at: 570))
        XCTAssertGreaterThanOrEqual(engine.progressFrac, 0.95, "the return leg's end, never the outbound leg's start")
        XCTAssertTrue(engine.isOnWay)
    }

    func testNoisyBeginReanchorsOnTheFirstOnWayFix() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.000898 * 2, lat: 0.0007, at: 0))   // 78 m north of the 200 m mark
        XCTAssertEqual(engine.startFrac, 0)
        XCTAssertFalse(engine.isOnWay)
        engine.processLocation(fix(lon: 0.000898 * 2, at: 5))
        XCTAssertEqual(engine.startFrac ?? -1, 0.2, accuracy: 0.02)
        XCTAssertEqual(engine.companionT0, 120, accuracy: 2)
    }

    func testReacquiresAfterSustainedOffWay() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0, at: 0))
        for s in stride(from: 10.0, through: 130, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898 * 4, lat: 0.01, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 140)
        engine.processLocation(fix(lon: 0.000898 * 4, at: 140))
        XCTAssertEqual(engine.progressFrac, 0.4, accuracy: 0.02, "global re-acquire takes the lowest frac within 60 m")
        XCTAssertTrue(engine.isOnWay)
    }

    func testInaccurateFixesAreIgnored() {
        let engine = makeEngine()
        engine.processLocation(fix(lon: 0.000898, accuracy: 60, at: 0))
        XCTAssertNil(engine.startFrac, "a 60 m fix must not anchor")
        engine.processLocation(fix(lon: 0.000898, accuracy: 20, at: 1))
        XCTAssertEqual(engine.startFrac ?? -1, 0.1, accuracy: 0.02)
    }

    func testProgressNeverMovesBackBeyondTheTolerance() {
        let engine = makeEngine(way: straightWay())
        engine.processLocation(fix(lon: 0, at: 0))
        for i in 1...4 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        XCTAssertEqual(engine.progressFrac, 0.4, accuracy: 0.02)
        engine.processLocation(fix(lon: 0.000898 * 3.5, at: 270))   // 50 m back along the line
        XCTAssertEqual(engine.progressFrac, 0.4 - HonorTuning.backwardTolerance, accuracy: 0.005,
                       "clamped to the window's lower edge, not frozen and not further back")
    }

    func testSoftTapDisabledNeverFires() {
        let engine = HonorEngine(way: outAndBackWay(), softTapEnabled: false, voicesEnabled: true, now: { self.clock })
        var taps = 0
        let sub = engine.events.sink { if case .softTap = $0 { taps += 1 } }
        defer { sub.cancel() }
        engine.processLocation(fix(lon: 0.000898, at: 0))
        for s in stride(from: 10.0, through: 300, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898, lat: 0.0036, at: s))
        }
        XCTAssertEqual(taps, 0)
    }

    func testStationaryJitterNeverAdvancesTheWalk() {
        let engine = makeEngine(way: straightWay())
        engine.processLocation(fix(lon: 0.000898 * 5, at: 0))
        XCTAssertEqual(engine.startFrac ?? -1, 0.5, accuracy: 0.02)
        for s in stride(from: 1.0, through: 600, by: 1) {
            let jitter = (Int(s) % 2 == 0) ? 0.0003 : -0.0003     // ~33 m either side
            let speed = (Int(s) % 3 == 0) ? -1.0 : 0.0              // speed is irrelevant to the gate; vary it anyway
            engine.processLocation(fix(lon: 0.000898 * 5 + jitter, speed: speed, at: s))
        }
        XCTAssertLessThan(engine.distanceWalkedMeters, 50)
        XCTAssertLessThan(engine.progressFrac, 0.56)
    }

    func testUnknownSpeedStillReachesArrival() {
        let engine = makeEngine(way: straightWay())
        var arrived = 0
        let sub = engine.events.sink { if case .arrived = $0 { arrived += 1 } }
        defer { sub.cancel() }
        for i in 0...10 { engine.processLocation(fix(lon: 0.000898 * Double(i), speed: -1, at: Double(i) * 60)) }
        for i in 0..<3 { engine.processLocation(fix(lon: 0.000898 * 10, speed: -1, at: 660 + Double(i))) }
        XCTAssertEqual(arrived, 1, "a stream with no speed values must still arrive")
    }

    func testMidWayBeginCanStillArrive() {
        let engine = makeEngine(way: straightWay())
        var arrived = 0
        let sub = engine.events.sink { if case .arrived = $0 { arrived += 1 } }
        defer { sub.cancel() }
        for i in 6...10 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i - 6) * 60)) }
        XCTAssertEqual(engine.startFrac ?? -1, 0.6, accuracy: 0.02)
        for i in 0..<3 { engine.processLocation(fix(lon: 0.000898 * 10, at: 300 + Double(i))) }
        XCTAssertEqual(arrived, 1, "half of what lay ahead at Begin is enough")
    }

    func testReacquireCorrectsPositionWithoutCreditingDistance() {
        let engine = makeEngine(way: straightWay())
        var arrived = 0
        let sub = engine.events.sink { if case .arrived = $0 { arrived += 1 } }
        defer { sub.cancel() }
        engine.processLocation(fix(lon: 0, at: 0))
        for i in 1...2 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        XCTAssertEqual(engine.distanceWalkedMeters, 200, accuracy: 10)
        // Off the Way for over two minutes, then rejoin far ahead at 800 m (outside the 300 m window).
        for s in stride(from: 130.0, through: 260, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898 * 4, lat: 0.0036, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 270)
        engine.processLocation(fix(lon: 0.000898 * 8, at: 270))
        XCTAssertEqual(engine.progressFrac, 0.8, accuracy: 0.02, "position corrected")
        XCTAssertEqual(engine.distanceWalkedMeters, 200, accuracy: 10, "the jump earned nothing")
        for i in 0..<4 { engine.processLocation(fix(lon: 0.000898 * 10, at: 400 + Double(i))) }
        XCTAssertEqual(engine.distanceWalkedMeters, 400, accuracy: 20)
        XCTAssertEqual(arrived, 0, "400 m walked of 1000 ahead is under the half required")
    }

    func testSoftTapStopsAfterArrival() {
        let engine = makeEngine(way: straightWay())
        var taps = 0
        let sub = engine.events.sink { if case .softTap = $0 { taps += 1 } }
        defer { sub.cancel() }
        for i in 0...10 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        for i in 0..<3 { engine.processLocation(fix(lon: 0.000898 * 10, at: 660 + Double(i))) }
        XCTAssertEqual(engine.phase, .arrived)
        for s in stride(from: 700.0, through: 900, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898 * 10, lat: 0.0036, at: s))
        }
        XCTAssertEqual(taps, 0)
    }

    func testStopCancelsTheBoundStreams() {
        let engine = makeEngine()
        let locations = PassthroughSubject<CLLocation, Never>()
        let duration = PassthroughSubject<TimeInterval, Never>()
        let flag = PassthroughSubject<Bool, Never>()
        engine.bind(locations: locations.eraseToAnyPublisher(), activeDuration: duration.eraseToAnyPublisher(),
                    isPaused: flag.eraseToAnyPublisher(), isMeditating: flag.eraseToAnyPublisher(),
                    isRecordingVoice: flag.eraseToAnyPublisher(), externalAudio: flag.eraseToAnyPublisher())
        locations.send(fix(lon: 0.000898, at: 0))
        settleCombineSchedulers()
        XCTAssertEqual(engine.startFrac ?? -1, 0.1, accuracy: 0.02)
        duration.send(60)
        settleCombineSchedulers()
        XCTAssertEqual(engine.companionFrac, 0.2, accuracy: 0.02)
        engine.stop()
        locations.send(fix(lon: 0.000898 * 3, at: 60))
        duration.send(600)
        settleCombineSchedulers()
        XCTAssertEqual(engine.progressFrac, 0.1, accuracy: 0.02, "nothing moves after stop()")
        XCTAssertEqual(engine.companionFrac, 0.2, accuracy: 0.02, "the clock stops too")
    }
}
