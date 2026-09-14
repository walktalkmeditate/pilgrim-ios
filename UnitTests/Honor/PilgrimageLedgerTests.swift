import XCTest
@testable import Pilgrim

final class PilgrimageLedgerTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func ledger() -> PilgrimageLedger {
        PilgrimageLedger(routeId: "camino-frances")
    }

    private func stage(_ index: Int, name: String, km: Double) -> WayStage {
        WayStage(routeId: "camino-frances", index: index, count: 33, name: name, theme: "t",
                 narrative: "n", closing: "c", warnings: [], distanceKm: km, gainMeters: 100,
                 hours: WayStageHours(min: 5, max: 7), difficulty: "moderate",
                 start: WayStagePlace(name: "a", at: WayCoordinate(lat: 0, lon: 0)),
                 end: WayStagePlace(name: "b", at: WayCoordinate(lat: 0, lon: 0.01)))
    }

    private func routeStage(_ index: Int, name: String, km: Double) -> PilgrimageRouteStage {
        PilgrimageRouteStage(index: index, name: name, distanceKm: km, gainMeters: 100,
                             hours: WayStageHours(min: 5, max: 7), difficulty: "moderate")
    }

    // MARK: - Recording

    func testACompletedStageAndAPartialOneAreBothRemembered() {
        var led = ledger()
        led.record(stageIndex: 0, name: "SJPP to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: day)
        XCTAssertEqual(led.stages["0"]?.completed, true)
        XCTAssertEqual(led.stages["0"]?.kmWalked ?? 0, 24.2, accuracy: 0.01)
        XCTAssertNil(led.stages["0"]?.stoppedAtFrac)
        XCTAssertEqual(led.stages["1"]?.completed, false)
        XCTAssertEqual(led.stages["1"]?.stoppedAtFrac ?? 0, 0.58, accuracy: 0.001)
        XCTAssertEqual(led.stages["1"]?.kmWalked ?? 0, 21.9 * 0.58, accuracy: 0.01)
        XCTAssertEqual(led.totalKmWalked, 24.2 + 21.9 * 0.58, accuracy: 0.01)
        XCTAssertEqual(led.completedCount, 1)
    }

    func testASecondWalkOfTheSameStageNeverLosesGround() {
        var led = ledger()
        led.record(stageIndex: 0, name: "s", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 0, name: "s", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 0.2, arrived: false), at: day.addingTimeInterval(86_400))
        XCTAssertEqual(led.stages["0"]?.completed, true, "walking it again half-way does not un-walk it")
        XCTAssertEqual(led.stages["0"]?.kmWalked ?? 0, 24.2, accuracy: 0.01)
    }

    // MARK: - The next row

    func testNextOffersTheFirstUnwalkedStageAndResumesAPartialOne() {
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        XCTAssertEqual(led.next(stageCount: 3), PilgrimageLedger.Next(index: 1, resumeFrac: nil))
        led.record(stageIndex: 1, name: "b", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 0.58, arrived: false), at: day)
        XCTAssertEqual(led.next(stageCount: 3), PilgrimageLedger.Next(index: 1, resumeFrac: 0.58))
        led.record(stageIndex: 1, name: "b", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 2, name: "c", distanceKm: 20,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        XCTAssertNil(led.next(stageCount: 3), "every stage walked")
    }

    func testAnEmptyLedgerOffersTheFirstStage() {
        XCTAssertEqual(PilgrimageLedger(routeId: "x").next(stageCount: 33),
                       PilgrimageLedger.Next(index: 0, resumeFrac: nil))
    }

    func testProgressLineReadsTheStageYouAreOn() {
        var led = ledger()
        XCTAssertEqual(PilgrimageLedger.progressLine(ledger: nil, stageCount: 33), "33 stages")
        for index in 0..<4 {
            led.record(stageIndex: index, name: "s\(index)", distanceKm: 28,
                       outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        }
        XCTAssertEqual(PilgrimageLedger.progressLine(ledger: led, stageCount: 33),
                       "stage 5 of 33 · \(StatsHelper.string(for: 112_000, unit: UnitLength.meters, type: .distance)) walked")
        for index in 4..<33 {
            led.record(stageIndex: index, name: "s\(index)", distanceKm: 10,
                       outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        }
        XCTAssertTrue(PilgrimageLedger.progressLine(ledger: led, stageCount: 33).hasPrefix("you have walked the whole way"))
    }

    // MARK: - Identity across an update

    func testReconcileKeepsStagesWhoseIdentityHeldAndCarriesTheRestsKilometres() {
        var led = ledger()
        led.record(stageIndex: 0, name: "SJPP to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        led.record(stageIndex: 2, name: "Zubiri to Pamplona", distanceKm: 20.4,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)

        let reconciled = led.reconciled(against: [
            routeStage(0, name: "SJPP to Roncesvalles", km: 24.2),          // identical
            routeStage(1, name: "Roncesvalles to Zubiri", km: 22.7),        // 3.7% — inside 5%
            routeStage(2, name: "Zubiri to Larrasoaña", km: 20.4)           // renamed
        ])
        XCTAssertEqual(Set(reconciled.stages.keys), ["0", "1"])
        XCTAssertEqual(reconciled.carriedKm ?? 0, 20.4, accuracy: 0.01, "the dropped stage's kilometres are kept")
        XCTAssertEqual(reconciled.totalKmWalked, 24.2 + 21.9 + 20.4, accuracy: 0.01)
        XCTAssertEqual(reconciled.redrawNoticePending, true)
    }

    func testAStageWhoseDistanceMovedMoreThanFivePercentIsDropped() {
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 20,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        let reconciled = led.reconciled(against: [routeStage(0, name: "a", km: 21.5)])   // 7.5%
        XCTAssertTrue(reconciled.stages.isEmpty)
        XCTAssertEqual(reconciled.carriedKm ?? 0, 20, accuracy: 0.01)
    }

    func testAnUnchangedRouteRaisesNoNotice() {
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 20,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        let reconciled = led.reconciled(against: [routeStage(0, name: "a", km: 20)])
        XCTAssertEqual(reconciled.stages.count, 1)
        XCTAssertNil(reconciled.redrawNoticePending)
        XCTAssertNil(reconciled.carriedKm)
    }

    // MARK: - The writer

    func testNothingIsWrittenWithoutAnAnchor() {
        XCTAssertNil(PilgrimageLedgerWriter.entry(stage: stage(0, name: "a", km: 24.2), outcome: nil),
                     "the engine never anchored on the Way: no stage was walked")
        let written = PilgrimageLedgerWriter.entry(
            stage: stage(3, name: "a", km: 24.2),
            outcome: HonorStageOutcome(progressFrac: 0.4, arrived: false))
        XCTAssertEqual(written?.index, 3)
        XCTAssertEqual(written?.distanceKm, 24.2)
    }

    // MARK: - The file

    func testTheLedgerOutlivesTheStages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let wayStore = WayStore(baseDirectory: dir)
        let store = PilgrimageLedgerStore(store: wayStore)
        var led = ledger()
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: day)
        store.save(led)
        XCTAssertEqual(store.load(routeId: "camino-frances")?.completedCount, 1)

        // Remove takes the stage Ways; the package folder's ledger stays.
        wayStore.delete(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0))
        XCTAssertEqual(store.load(routeId: "camino-frances")?.completedCount, 1)
        XCTAssertNil(store.load(routeId: "../etc"))
    }
}
