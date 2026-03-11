import XCTest
@testable import Pilgrim

final class ComputationTests: XCTestCase {

    // MARK: - calculateElevationData

    func testElevation_emptyAltitudes_returnsZero() {
        let result = Computation.calculateElevationData(from: [])
        XCTAssertEqual(result.ascending, 0)
        XCTAssertEqual(result.descending, 0)
    }

    func testElevation_singleAltitude_returnsZero() {
        let result = Computation.calculateElevationData(from: [100.0])
        XCTAssertEqual(result.ascending, 0)
        XCTAssertEqual(result.descending, 0)
    }

    func testElevation_flatTerrain_returnsZero() {
        let altitudes = Array(repeating: 100.0, count: 20)
        let result = Computation.calculateElevationData(from: altitudes)
        XCTAssertEqual(result.ascending, 0, accuracy: 0.01)
        XCTAssertEqual(result.descending, 0, accuracy: 0.01)
    }

    func testElevation_steadyClimb_ascendingOnly() {
        let altitudes = Array(stride(from: 0.0, through: 200.0, by: 5.0))
        let result = Computation.calculateElevationData(from: altitudes)
        XCTAssertGreaterThan(result.ascending, 0)
        XCTAssertEqual(result.descending, 0, accuracy: 0.01)
    }

    func testElevation_steadyDescent_descendingOnly() {
        let altitudes = Array(stride(from: 200.0, through: 0.0, by: -5.0))
        let result = Computation.calculateElevationData(from: altitudes)
        XCTAssertEqual(result.ascending, 0, accuracy: 0.01)
        XCTAssertGreaterThan(result.descending, 0)
    }

    func testElevation_smallFluctuationsBelowThreshold_ignored() {
        var altitudes: [Double] = []
        for i in 0..<30 {
            altitudes.append(100.0 + (i.isMultiple(of: 2) ? 0.0 : 0.5))
        }
        let result = Computation.calculateElevationData(from: altitudes)
        XCTAssertEqual(result.ascending, 0, accuracy: 0.01)
        XCTAssertEqual(result.descending, 0, accuracy: 0.01)
    }

    func testElevation_largeFluctuations_counted() {
        let altitudes = Array(repeating: 0.0, count: 20) + Array(repeating: 50.0, count: 20)
        let result = Computation.calculateElevationData(from: altitudes)
        XCTAssertGreaterThan(result.ascending, 0)
    }

    func testElevation_mixedTerrain_bothNonzero() {
        let up = Array(stride(from: 0.0, through: 100.0, by: 5.0))
        let flat = Array(repeating: 100.0, count: 15)
        let down = Array(stride(from: 100.0, through: 0.0, by: -5.0))
        let altitudes = up + flat + down
        let result = Computation.calculateElevationData(from: altitudes)
        XCTAssertGreaterThan(result.ascending, 0)
        XCTAssertGreaterThan(result.descending, 0)
    }

    // MARK: - calculateDurationData

    func testDuration_noPauses_fullActiveDuration() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let result = Computation.calculateDurationData(from: start, end: end)
        XCTAssertEqual(result.activeDuration, 3600, accuracy: 0.01)
        XCTAssertEqual(result.pauseDuration, 0, accuracy: 0.01)
    }

    func testDuration_singlePause_correctlySubtracted() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let pauses: [Computation.RawPauseTouple] = [
            (start: DateFactory.makeDate(2024, 6, 15, 9, 20, 0),
             end: DateFactory.makeDate(2024, 6, 15, 9, 30, 0))
        ]
        let result = Computation.calculateDurationData(from: start, end: end, pauses: pauses)
        XCTAssertEqual(result.activeDuration, 3000, accuracy: 0.01)
        XCTAssertEqual(result.pauseDuration, 600, accuracy: 0.01)
    }

    func testDuration_multiplePauses_allSubtracted() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let pauses: [Computation.RawPauseTouple] = [
            (start: DateFactory.makeDate(2024, 6, 15, 9, 10, 0),
             end: DateFactory.makeDate(2024, 6, 15, 9, 15, 0)),
            (start: DateFactory.makeDate(2024, 6, 15, 9, 30, 0),
             end: DateFactory.makeDate(2024, 6, 15, 9, 40, 0))
        ]
        let result = Computation.calculateDurationData(from: start, end: end, pauses: pauses)
        XCTAssertEqual(result.activeDuration, 2700, accuracy: 0.01)
        XCTAssertEqual(result.pauseDuration, 900, accuracy: 0.01)
    }

    func testDuration_zeroLengthPause_noEffect() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let pauseTime = DateFactory.makeDate(2024, 6, 15, 9, 30, 0)
        let pauses: [Computation.RawPauseTouple] = [(start: pauseTime, end: pauseTime)]
        let result = Computation.calculateDurationData(from: start, end: end, pauses: pauses)
        XCTAssertEqual(result.activeDuration, 3600, accuracy: 0.01)
        XCTAssertEqual(result.pauseDuration, 0, accuracy: 0.01)
    }

    // MARK: - calculateAndValidatePauses

    func testPauses_emptyEvents_returnsEmptyArray() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let result = Computation.calculateAndValidatePauses(from: [], walkStart: start, walkEnd: end)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 0)
    }

    func testPauses_validManualPauseResume_returnsPause() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 0, date: DateFactory.makeDate(2024, 6, 15, 9, 20, 0)),
            (type: 2, date: DateFactory.makeDate(2024, 6, 15, 9, 25, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.type, 0)
    }

    func testPauses_validAutoPauseResume_returnsPause() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 1, date: DateFactory.makeDate(2024, 6, 15, 9, 20, 0)),
            (type: 3, date: DateFactory.makeDate(2024, 6, 15, 9, 25, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.type, 1)
    }

    func testPauses_eventOutsideWalkRange_returnsNil() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 0, date: DateFactory.makeDate(2024, 6, 15, 8, 50, 0)),
            (type: 2, date: DateFactory.makeDate(2024, 6, 15, 9, 5, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNil(result)
    }

    func testPauses_resumeBeforePause_returnsNil() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 2, date: DateFactory.makeDate(2024, 6, 15, 9, 20, 0)),
            (type: 0, date: DateFactory.makeDate(2024, 6, 15, 9, 25, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNil(result)
    }

    func testPauses_moreResumesThanPauses_returnsNil() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 0, date: DateFactory.makeDate(2024, 6, 15, 9, 10, 0)),
            (type: 2, date: DateFactory.makeDate(2024, 6, 15, 9, 15, 0)),
            (type: 2, date: DateFactory.makeDate(2024, 6, 15, 9, 20, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNil(result)
    }

    func testPauses_unmatchedPauseAtEnd_usesWalkEnd() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 0, date: DateFactory.makeDate(2024, 6, 15, 9, 50, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.end, end)
    }

    func testPauses_sameRangeManualAndAuto_mergedAsAuto() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let pauseStart = DateFactory.makeDate(2024, 6, 15, 9, 20, 0)
        let pauseEnd = DateFactory.makeDate(2024, 6, 15, 9, 25, 0)
        let events: [Computation.EventTouple] = [
            (type: 0, date: pauseStart),
            (type: 1, date: pauseStart),
            (type: 2, date: pauseEnd),
            (type: 3, date: pauseEnd)
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.type, 1)
    }

    func testPauses_highEventTypesFiltered() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let end = DateFactory.makeDate(2024, 6, 15, 10, 0, 0)
        let events: [Computation.EventTouple] = [
            (type: 5, date: DateFactory.makeDate(2024, 6, 15, 9, 20, 0)),
            (type: 10, date: DateFactory.makeDate(2024, 6, 15, 9, 30, 0))
        ]
        let result = Computation.calculateAndValidatePauses(from: events, walkStart: start, walkEnd: end)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 0)
    }

    // MARK: - calculateBurnedEnergy

    func testBurnedEnergy_walking_expectedResult() {
        let result = Computation.calculateBurnedEnergy(for: .walking, distance: 5000, weight: 70)
        XCTAssertEqual(result, 229.25, accuracy: 0.01)
    }

    func testBurnedEnergy_unknownType_returnsZero() {
        let result = Computation.calculateBurnedEnergy(for: .unknown, distance: 5000, weight: 70)
        XCTAssertEqual(result, 0)
    }

    func testBurnedEnergy_zeroDistance_returnsZero() {
        let result = Computation.calculateBurnedEnergy(for: .walking, distance: 0, weight: 70)
        XCTAssertEqual(result, 0)
    }
}
