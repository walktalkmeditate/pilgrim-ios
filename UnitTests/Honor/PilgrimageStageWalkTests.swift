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

extension PilgrimageStageWalkTests {

    func testTheStageLineStandsWhereADateWould() {
        let way = stageWay()
        XCTAssertEqual(WayStageLine.line(for: way),
                       "stage 1 of 33 · \(StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance)) · hard")
        var notAStage = way
        notAStage.stage = nil
        XCTAssertNil(WayStageLine.line(for: notAStage), "a shared walk still shows its date")
        XCTAssertTrue(way.isPilgrimageStage)
        XCTAssertFalse(notAStage.isPilgrimageStage)
    }

    /// The engine's `softTapEnabled` is what actually gates the soft tap —
    /// driving fixes off the line and reading `softTapCaption` can't prove
    /// this, since the first fix anchors by fallback (no soft tap while
    /// approaching) and the view model's engine runs on the real clock, so
    /// the 120 s window never elapses in a synchronous test either way.
    func testAStageWalksWithNoCompanionAndNoSoftTap() {
        UserPreferences.honorSoftTapEnabled.value = true
        addTeardownBlock { UserPreferences.honorSoftTapEnabled.delete() }
        let vm = ActiveWalkViewModel(mode: .honor, way: stageWay())
        vm.builder.setStatus(.ready)
        vm.startRecording()
        XCTAssertNotNil(vm.honorEngine)
        XCTAssertNil(vm.companionCoordinate, "the stage's own voice walks with you, not a dot")
        XCTAssertEqual(vm.honorEngine?.softTapEnabled, false, "a stage has no companion to be off the way from")
        vm.teardownHonor()
    }

    /// The positive control for the assertion above: an own walk keeps both
    /// its companion dot and the soft tap the preference asked for.
    func testAnOwnWalkWayKeepsItsCompanion() {
        UserPreferences.honorSoftTapEnabled.value = true
        addTeardownBlock { UserPreferences.honorSoftTapEnabled.delete() }
        var way = stageWay()
        way.stage = nil
        let vm = ActiveWalkViewModel(mode: .honor, way: way)
        vm.builder.setStatus(.ready)
        vm.startRecording()
        vm.honorEngine?.processLocation(
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start))
        XCTAssertNotNil(vm.companionCoordinate)
        XCTAssertEqual(vm.honorEngine?.softTapEnabled, true, "an own walk still has a companion to fall off the way from")
        vm.teardownHonor()
    }

    func testTheArrivalCardForAStageNamesTheStageAndCarriesNoDelta() {
        let card = HonorArrivalCard(wayTitle: "Saint-Jean-Pied-de-Port to Roncesvalles",
                                    voicesHeard: 0, placesPassed: 3, theirSeconds: 0, yourSeconds: 0,
                                    stageName: "Saint-Jean-Pied-de-Port to Roncesvalles",
                                    distanceWalkedMeters: 24_200)
        XCTAssertEqual(HonorArrivalCardView.title(for: card), "you walked the stage")
        XCTAssertTrue(HonorArrivalCardView.line(for: card).contains("3 places passed"))
        XCTAssertTrue(HonorArrivalCardView.line(for: card)
            .contains(StatsHelper.string(for: 24_200, unit: UnitLength.meters, type: .distance)))

        let sharedWalk = HonorArrivalCard(wayTitle: "Rúa do Franco → Obradoiro", voicesHeard: 2,
                                          placesPassed: 1, theirSeconds: 600, yourSeconds: 540,
                                          stageName: nil, distanceWalkedMeters: 900)
        XCTAssertEqual(HonorArrivalCardView.title(for: sharedWalk), "you walked their way")
    }

    func testTheSummaryForAStageReadsKilometresAndNoCompanionDelta() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: start)
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start)])
        let data = HonorSummaryModel.summaryData(
            for: walk, way: stageWay(),
            link: WayLink(wayId: "pilgrimage:camino-frances:0", theirSeconds: 600, yourSeconds: 540),
            replies: [:], ledger: led)
        XCTAssertNil(data?.arrivedBeforeTheirsSeconds, "a stage has no companion to arrive before")
        let line = try? XCTUnwrap(data?.stageProgressLine)
        XCTAssertEqual(line?.hasSuffix("of the stage"), true, line ?? "nil")
        XCTAssertTrue(line?.contains(StatsHelper.string(for: 24.2 * 0.58 * 1000, unit: UnitLength.meters, type: .distance)) ?? false, line ?? "nil")
    }

    /// The summary block opens with a kicker that says "in their steps".
    /// A stage has no "their", and the flag is carried explicitly rather than
    /// inferred from the progress line — a walk that earned no ledger entry
    /// is still a stage walk.
    func testTheSummaryKickerDropsTheirStepsForAStage() throws {
        let walk = WalkDataFactory.makeWalk(
            uuid: UUID(), startDate: start, endDate: start.addingTimeInterval(3600),
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: start)])

        let stageData = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: walk, way: stageWay(), link: nil, replies: [:], ledger: nil))
        XCTAssertTrue(stageData.isPilgrimageStage)
        XCTAssertNil(stageData.stageProgressLine, "no ledger entry, but still a stage")
        XCTAssertEqual(HonorSummarySection.kicker(for: stageData), "the stage you walked")

        var notAStage = stageWay()
        notAStage.stage = nil
        let shared = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: walk, way: notAStage, link: nil, replies: [:], ledger: nil))
        XCTAssertFalse(shared.isPilgrimageStage)
        XCTAssertEqual(HonorSummarySection.kicker(for: shared), "in their steps")

        let removed = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: walk, way: nil, link: nil, replies: [:], ledger: nil))
        XCTAssertFalse(removed.isPilgrimageStage, "a Way that is gone says nothing about stages")
    }
}

extension PilgrimageStageWalkTests {

    private func waypoint(names: [String: String]?, label: String = "Vierge d'Orisson",
                          text: String? = nil, sitMinutes: Int? = nil) -> WayMoment {
        var moment = WayMoment(id: "wp-x", frac: 0.3, at: WayCoordinate(lat: 0, lon: 0),
                               kind: .waypoint(label: label, icon: "building.columns"))
        moment.names = names
        moment.text = text
        moment.sitMinutes = sitMinutes
        return moment
    }

    func testTheLocalNameFollowsAFixedOrderAndNeverEchoesTheLabel() {
        XCTAssertEqual(WayMomentHeader.localName(for: waypoint(names: ["es": "Virgen de Orisson",
                                                                      "eu": "Orissongo Ama Birjina",
                                                                      "fr": "Vierge d'Orisson"])),
                       "Orissongo Ama Birjina", "eu comes first")
        XCTAssertEqual(WayMomentHeader.localName(for: waypoint(names: ["es": "Virgen de Orisson",
                                                                      "fr": "Vierge d'Orisson"])),
                       "Virgen de Orisson", "the French name is the label; es is next in order")
        XCTAssertNil(WayMomentHeader.localName(for: waypoint(names: ["fr": "Vierge d'Orisson"])),
                     "the only local name is the label itself")
        XCTAssertNil(WayMomentHeader.localName(for: waypoint(names: nil)))
        XCTAssertNil(WayMomentHeader.localName(for: waypoint(names: ["ru": "Орисон"])),
                     "a language outside the order is not shown")
    }

    func testThePlaceCopyChangesForAStage() {
        XCTAssertEqual(WayMomentHeader.placeCopy(for: waypoint(names: nil), isStage: true),
                       "A place on the way.")
        XCTAssertEqual(WayMomentHeader.placeCopy(for: waypoint(names: nil), isStage: false),
                       "A place they marked.")
        XCTAssertEqual(WayMomentHeader.placeCopy(for: waypoint(names: nil, text: "A shepherd carried this Madonna."),
                                                 isStage: true),
                       "A shepherd carried this Madonna.")
    }

    func testAPinDrawsAtItsOwnCoordinateWhileTheTriggerStaysOnTheLine() {
        let way = stageWay()
        let pins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: [])
        let pin = try? XCTUnwrap(pins.first { $0.kind.wayMomentID == "wp-orisson" })
        XCTAssertEqual(pin?.coordinate.latitude ?? 0, 0.0002, accuracy: 1e-9, "drawn at `pin`")
        XCTAssertEqual(way.moments[0].at?.lat, 0, "triggered on the line")
    }
}
