import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

/// Walking a stage: what the engine, the view model, and the coordinator do
/// differently when the Way came from a pilgrimage package.
final class PilgrimageStageWalkTests: XCTestCase {

    let start = Date(timeIntervalSince1970: 1_000_000)

    /// A 1 km stage running east along the equator, so every distance below
    /// is arithmetic: 0.000898° of longitude is 100 m.
    func stageWay(index: Int = 0, marks: [WayMark] = []) -> Way {
        var moment = WayMoment(id: "wp-orisson", frac: 0.3, at: WayCoordinate(lat: 0, lon: 300 / 111_320),
                               kind: .waypoint(label: "Vierge d'Orisson", icon: "building.columns"))
        moment.text = "A shepherd carried this Madonna up from Lourdes."
        moment.names = ["eu": "Orissongo Ama Birjina", "fr": "Vierge d'Orisson"]
        moment.sitMinutes = 5
        moment.pin = WayCoordinate(lat: 0.0002, lon: 300 / 111_320)
        var way = Way(
            id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: index),
            source: .pilgrimage(routeId: "camino-frances", stageIndex: index),
            title: "Saint-Jean-Pied-de-Port to Roncesvalles",
            departedAt: start, tzIdentifier: "Europe/Madrid", expires: nil,
            route: (0...10).map { WayPoint(lat: 0, lon: Double($0) * 0.000898, alt: nil, t: Double($0) * 60) },
            totalDistanceMeters: 1000, theirActiveSeconds: 600,
            moments: [moment], weather: nil)
        way.marks = marks
        way.stage = WayStage(
            routeId: "camino-frances", index: index, count: 33,
            name: "Saint-Jean-Pied-de-Port to Roncesvalles", theme: "Initiation",
            narrative: "The Pyrenees are the first question the way asks.",
            closing: "You crossed a border on foot.",
            warnings: ["The Napoleon Route closes in winter."],
            distanceKm: 24.2, gainMeters: 1419, hours: WayStageHours(min: 7, max: 9), difficulty: "hard",
            start: WayStagePlace(name: "Saint-Jean-Pied-de-Port", at: WayCoordinate(lat: 0, lon: 0)),
            end: WayStagePlace(name: "Roncesvalles", at: WayCoordinate(lat: 0, lon: 0.00898)))
        return way
    }

    func testTheEngineReportsWhetherItEverAnchoredOnTheWay() {
        let engine = HonorEngine(way: stageWay(), softTapEnabled: false, voicesEnabled: false)
        XCTAssertFalse(engine.isAnchoredOnWay, "no fix yet")
        // A kilometre north of the line: Begin falls back to frac 0.
        engine.processLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.01, longitude: 0),
                                          altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                          timestamp: start))
        XCTAssertFalse(engine.isAnchoredOnWay, "the frac-0 fallback is not a stage joined")
        engine.processLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.000898),
                                          altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                          timestamp: start.addingTimeInterval(60)))
        XCTAssertTrue(engine.isAnchoredOnWay)
    }

    func testTheOutcomeSurvivesTeardown() {
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        let engine = try? XCTUnwrap(vm.honorEngine)
        engine?.processLocation(CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.002694),
                                           altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                           timestamp: start))
        vm.teardownHonor()
        let outcome = vm.honorStageOutcome
        XCTAssertNotNil(outcome, "the engine is gone by the time the walk is saved")
        XCTAssertEqual(outcome?.progressFrac ?? 0, 0.3, accuracy: 0.02)
        XCTAssertFalse(outcome?.arrived ?? true)
    }

    func testNoOutcomeWithoutAnAnchor() {
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        vm.honorEngine?.processLocation(
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.01, longitude: 0),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start))
        vm.teardownHonor()
        XCTAssertNil(vm.honorStageOutcome)
    }

    @MainActor
    func testTheCoordinatorWritesTheStageIntoTheRoutesLedger() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        let ledgers = PilgrimageLedgerStore(store: store)
        let coordinator = MainCoordinator()
        coordinator.pilgrimageLedgers = ledgers

        coordinator.recordStageWalk(way: stageWay(index: 4),
                                    outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false),
                                    at: start)

        let ledger = try XCTUnwrap(ledgers.load(routeId: "camino-frances"))
        XCTAssertEqual(ledger.stages["4"]?.name, "Saint-Jean-Pied-de-Port to Roncesvalles")
        XCTAssertEqual(ledger.stages["4"]?.stoppedAtFrac ?? 0, 0.58, accuracy: 0.001)
        XCTAssertEqual(ledger.stages["4"]?.completed, false)
        XCTAssertEqual(ledger.next(stageCount: 33), PilgrimageLedger.Next(index: 0, resumeFrac: nil),
                       "stages 0 to 3 are still unwalked")
    }

    @MainActor
    func testNothingIsWrittenForAWayThatIsNotAStageOrAWalkThatNeverJoined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let ledgers = PilgrimageLedgerStore(store: WayStore(baseDirectory: dir))
        let coordinator = MainCoordinator()
        coordinator.pilgrimageLedgers = ledgers

        coordinator.recordStageWalk(way: stageWay(), outcome: nil, at: start)
        XCTAssertNil(ledgers.load(routeId: "camino-frances"))

        var notAStage = stageWay()
        notAStage.stage = nil
        coordinator.recordStageWalk(way: notAStage,
                                    outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: start)
        XCTAssertNil(ledgers.load(routeId: "camino-frances"))
    }
}
