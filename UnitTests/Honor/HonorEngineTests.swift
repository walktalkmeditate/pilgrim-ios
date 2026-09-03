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
        XCTAssertEqual(geo.lowestFrac(within: 60, of: probe)?.frac ?? -1, 0.25, accuracy: 0.01)
        XCTAssertEqual(geo.lowestFrac(within: 60, of: probe, from: 0.5)?.frac ?? -1, 0.75, accuracy: 0.01)
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

    func testReacquireIsCreditedAtTheWaysOwnPace() {
        let engine = makeEngine(way: straightWay())
        var arrived = 0
        let sub = engine.events.sink { if case .arrived = $0 { arrived += 1 } }
        defer { sub.cancel() }
        engine.processLocation(fix(lon: 0, at: 0))
        for i in 1...2 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        XCTAssertEqual(engine.distanceWalkedMeters, 200, accuracy: 10)
        // Off the Way for over two minutes, then rejoin far ahead at 800 m (outside the 300 m window).
        // Pace credit is earned on WALKING time, so the active-duration
        // stream advances with the clock here exactly as on a real walk.
        for s in stride(from: 130.0, through: 260, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.updateActiveDuration(s)
            engine.processLocation(fix(lon: 0.000898 * 4, lat: 0.0036, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 270)
        engine.updateActiveDuration(270)
        engine.processLocation(fix(lon: 0.000898 * 8, at: 270))
        XCTAssertEqual(engine.progressFrac, 0.8, accuracy: 0.02, "position corrected")
        XCTAssertEqual(engine.distanceWalkedMeters, 200 + 233, accuracy: 15, "credited at the Way's pace, not the 600 m jump")
        clock = Date(timeIntervalSince1970: 1_000_000 + 400)
        engine.updateActiveDuration(400)
        for i in 0..<4 { engine.processLocation(fix(lon: 0.000898 * 10, at: 400 + Double(i))) }
        XCTAssertEqual(engine.distanceWalkedMeters, 633, accuracy: 25)
        XCTAssertEqual(arrived, 1, "an honest walker who lost signal still arrives")
    }

    /// The honest case the pace credit exists for: signal lost through a
    /// corner, back on the line 450 m later after five minutes. The stretch
    /// is credited in full because it is under the Way's pace; a pace-only
    /// implementation would credit 500 m here.
    func testHonestOffSignalStretchIsCreditedInFull() {
        let engine = makeEngine(way: straightWay())
        engine.processLocation(fix(lon: 0, at: 0))
        for i in 1...2 { engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60)) }
        XCTAssertEqual(engine.distanceWalkedMeters, 200, accuracy: 10)
        for s in stride(from: 210.0, through: 500, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.updateActiveDuration(s)
            engine.processLocation(fix(lon: 0.000898 * 3.5, lat: 0.0036, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 510)
        engine.updateActiveDuration(510)
        engine.processLocation(fix(lon: 0.000898 * 6.5, at: 510))
        XCTAssertEqual(engine.progressFrac, 0.65, accuracy: 0.02)
        XCTAssertEqual(engine.distanceWalkedMeters, 650, accuracy: 15, "the 450 m jump is under 300 s of the Way's pace, so it counts in full")
    }

    func testReacquireCannotOutrunTheWaysPace() {
        let engine = makeEngine(way: straightWay())
        var arrived = 0
        let sub = engine.events.sink { if case .arrived = $0 { arrived += 1 } }
        defer { sub.cancel() }
        engine.processLocation(fix(lon: 0, at: 0))
        engine.processLocation(fix(lon: 0.000898, at: 60))
        XCTAssertEqual(engine.distanceWalkedMeters, 100, accuracy: 10)
        // Drive 800 m in a car: off the line from 70 s, back on it at 900 m at 210 s.
        for s in stride(from: 70.0, through: 200, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.updateActiveDuration(s)
            engine.processLocation(fix(lon: 0.000898 * 5, lat: 0.0036, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 210)
        engine.updateActiveDuration(210)
        engine.processLocation(fix(lon: 0.000898 * 9, at: 210))
        XCTAssertEqual(engine.progressFrac, 0.9, accuracy: 0.02)
        XCTAssertEqual(engine.distanceWalkedMeters, 100 + 233, accuracy: 15, "140 s off the Way earns 140 s of the Way's pace, not 800 m")
        clock = Date(timeIntervalSince1970: 1_000_000 + 300)
        engine.updateActiveDuration(300)
        for i in 0..<4 { engine.processLocation(fix(lon: 0.000898 * 10, at: 300 + Double(i))) }
        XCTAssertEqual(arrived, 0, "433 m earned of 1000 ahead is under the half required")
    }

    // MARK: - The re-anchor (A1, A2, A3)

    /// Begin away from the Way, walk eight minutes to the trailhead, join at
    /// frac 0: the companion starts where the walker does, and the approach
    /// counts toward neither clock.
    func testReanchorRestartsTheCompanionClockAndYourSeconds() {
        let engine = makeEngine(way: straightWay())
        engine.updateActiveDuration(0)
        engine.processLocation(fix(lon: 0.05, lat: 0.05, at: 0))
        XCTAssertEqual(engine.startFrac, 0, "no Way within 60 m — the fallback anchor")

        // Eight minutes of approach walking, still nowhere near the Way.
        engine.updateActiveDuration(480)
        clock = Date(timeIntervalSince1970: 1_000_000 + 480)
        engine.processLocation(fix(lon: 0, at: 480))
        XCTAssertEqual(engine.startFrac ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(engine.companionFrac, 0, accuracy: 0.001, "the companion starts at the re-anchor, not 800 m ahead")
        XCTAssertEqual(engine.distanceWalkedMeters, 0, accuracy: 0.001, "the re-anchor zeroes the arrival credit")

        engine.updateActiveDuration(540)
        XCTAssertEqual(engine.companionFrac, 0.1, accuracy: 0.02, "one minute past the re-anchor is one minute of their Way")
    }

    /// Before the real join, the fallback anchor gives the companion
    /// nowhere real to walk to — it must wait at the start rather than
    /// racing ahead on the approach walk's own active duration.
    func testCompanionWaitsAtTheStartDuringTheApproachWalk() {
        let engine = makeEngine(way: straightWay())
        engine.updateActiveDuration(0)
        engine.processLocation(fix(lon: 0.05, lat: 0.05, at: 0))
        XCTAssertEqual(engine.startFrac, 0, "no Way within 60 m — the fallback anchor")

        // Four minutes of approach walking, still nowhere near the Way.
        engine.updateActiveDuration(240)
        XCTAssertEqual(engine.companionFrac, 0, accuracy: 0.001, "the dot waits at the start until the Way is joined")

        // The real join, at the Way's own start.
        engine.updateActiveDuration(480)
        clock = Date(timeIntervalSince1970: 1_000_000 + 480)
        engine.processLocation(fix(lon: 0, at: 480))
        XCTAssertEqual(engine.companionFrac, 0, accuracy: 0.001, "still at the start the instant it joins")

        engine.updateActiveDuration(540)
        XCTAssertEqual(engine.companionFrac, 0.1, accuracy: 0.02, "the companion resumes once the Way is actually joined")
    }

    func testYourSecondsExcludesTheApproachWalk() {
        let engine = makeEngine(way: straightWay())
        var yours: Double?
        let sub = engine.events.sink { if case .arrived(_, let seconds) = $0 { yours = seconds } }
        defer { sub.cancel() }

        engine.updateActiveDuration(0)
        engine.processLocation(fix(lon: 0.05, lat: 0.05, at: 0))
        engine.updateActiveDuration(480)
        clock = Date(timeIntervalSince1970: 1_000_000 + 480)
        engine.processLocation(fix(lon: 0, at: 480))

        for i in 1...10 {
            let seconds = 480 + Double(i) * 60
            engine.updateActiveDuration(seconds)
            engine.processLocation(fix(lon: 0.000898 * Double(i), at: seconds))
        }
        engine.updateActiveDuration(1140)
        for i in 0..<4 { engine.processLocation(fix(lon: 0.000898 * 10, at: 1140 + Double(i))) }

        // 1140 s of walk, 480 s of it spent reaching the trailhead.
        XCTAssertEqual(yours ?? -1, 660, accuracy: 1, "the eight-minute approach is not part of the walker's time on the Way")
    }

    /// A2: the walker has not joined the Way yet, so "off the way" is the
    /// wrong word — the soft tap stays quiet until something is anchored.
    func testSoftTapStaysQuietDuringTheApproachWalk() {
        let engine = makeEngine(way: straightWay())
        var taps = 0
        let sub = engine.events.sink { if case .softTap = $0 { taps += 1 } }
        defer { sub.cancel() }

        for s in stride(from: 0.0, through: 200, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.updateActiveDuration(s)
            engine.processLocation(fix(lon: 0.05, lat: 0.05, at: s))
        }

        XCTAssertEqual(taps, 0, "nothing has been joined, so nothing has been left")
    }

    /// A3: a walk paused off the Way must not convert paused time into
    /// arrival credit — pace is earned by walking, not by waiting.
    func testPausedTimeOffTheWayEarnsNoPaceCredit() {
        let engine = makeEngine(way: straightWay())
        engine.updateActiveDuration(0)
        engine.processLocation(fix(lon: 0, at: 0))
        for i in 1...2 {
            engine.updateActiveDuration(Double(i) * 60)
            engine.processLocation(fix(lon: 0.000898 * Double(i), at: Double(i) * 60))
        }
        XCTAssertEqual(engine.distanceWalkedMeters, 200, accuracy: 10)

        // Five minutes pass on the wall clock with the walk paused: the
        // active-duration stream never moves.
        for s in stride(from: 130.0, through: 500, by: 10) {
            clock = Date(timeIntervalSince1970: 1_000_000 + s)
            engine.processLocation(fix(lon: 0.000898 * 4, lat: 0.0036, at: s))
        }
        clock = Date(timeIntervalSince1970: 1_000_000 + 510)
        engine.processLocation(fix(lon: 0.000898 * 8, at: 510))

        XCTAssertEqual(engine.progressFrac, 0.8, accuracy: 0.02, "position still corrects")
        XCTAssertEqual(engine.distanceWalkedMeters, 200, accuracy: 1, "paused time buys no credit")
    }

    // MARK: - Degenerate geometry

    func testEngineOnAWayOfIdenticalPointsDoesNotTrap() {
        let route = (0...4).map { i in WayPoint(lat: 0, lon: 0, alt: nil, t: Double(i) * 60) }
        let way = Way(id: "walk:degenerate", source: .ownWalk(UUID()), title: "still", departedAt: clock,
                      tzIdentifier: nil, expires: nil, route: route, totalDistanceMeters: 0,
                      theirActiveSeconds: 240, moments: [], weather: nil)
        let engine = HonorEngine(way: way, softTapEnabled: true, voicesEnabled: true, now: { self.clock })

        engine.updateActiveDuration(60)
        engine.processLocation(fix(lon: 0, at: 0))
        engine.processLocation(fix(lon: 0.05, lat: 0.05, at: 60))
        engine.updateActiveDuration(600)

        XCTAssertTrue(engine.offWayMeters.isFinite, "the no-segment sentinel must never reach a caller as an infinity")
        XCTAssertLessThanOrEqual(engine.offWayMeters, 100_000)
    }

    func testVoiceDidFinishWithNothingPlayingIsInert() {
        let engine = makeEngine(way: straightWay())
        var events: [HonorEngineEvent] = []
        let sub = engine.events.sink { events.append($0) }
        defer { sub.cancel() }

        engine.voiceDidFinish()
        engine.voiceDidFinish()

        XCTAssertTrue(events.isEmpty, "a finish for a voice that never started must say nothing")
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
