import XCTest
@testable import Pilgrim

final class DossierSensesTests: XCTestCase {

    // MARK: - Fixtures

    static let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    static let walkEnd = DateFactory.makeDate(2024, 6, 15, 10, 30, 0)

    func makeInput(
        currentWalkUUID: UUID = UUID(),
        walkStart: Date = DossierSensesTests.walkStart,
        walkEnd: Date = DossierSensesTests.walkEnd,
        totalAscent: Double = 0,
        elevationSeries: [DossierSenses.ElevationSample] = [],
        photos: [DossierSenses.PhotoPin] = [],
        currentRecordings: [DossierSenses.CurrentRecording] = [],
        threads: [WalkThread] = [],
        backfillComplete: Bool = true,
        walkSnapshots: [DossierSenses.WalkSnapshotRow] = [],
        historyTranscripts: [(recordingUUID: UUID, transcript: String)] = [],
        recordingTimestamps: [UUID: Date] = [:],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:],
        fixes: [UUID: DossierSenses.RouteFix] = [:],
        moon: DossierSenses.MoonInput? = nil
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: currentWalkUUID, walkStart: walkStart, walkEnd: walkEnd,
            totalAscent: totalAscent, elevationSeries: elevationSeries, photos: photos,
            currentRecordings: currentRecordings, threads: threads,
            backfillComplete: backfillComplete, walkSnapshots: walkSnapshots,
            historyTranscripts: historyTranscripts, recordingTimestamps: recordingTimestamps,
            walkIndex: walkIndex, fixes: fixes, moon: moon
        )
    }

    func fix(lat: Double, lon: Double, accuracy: Double = 10, gap: TimeInterval = 5) -> DossierSenses.RouteFix {
        DossierSenses.RouteFix(
            coordinate: DossierSenses.Coordinate(latitude: lat, longitude: lon),
            horizontalAccuracy: accuracy, gapSeconds: gap
        )
    }

    // MARK: - Engine: cap, priority, dedup

    private func stub(_ firing: [DossierSenses.Sense: DossierSenses.SenseLine])
        -> (DossierSenses.Sense, DossierSenses.Input, Set<String>) -> DossierSenses.SenseLine? {
        { sense, _, _ in firing[sense] }
    }

    func testEngine_fiveSensesFiring_exactlyThreeLinesInPriorityOrder() {
        let firing: [DossierSenses.Sense: DossierSenses.SenseLine] = [
            .speechShape: .init(text: "speech", lemma: nil),
            .climbAnchoring: .init(text: "climb", lemma: "river"),
            .placeResonance: .init(text: "place", lemma: "move"),
            .questionDensity: .init(text: "question", lemma: nil),
            .weatherWeave: .init(text: "weather", lemma: "music")
        ]
        let output = DossierSenses.lines(input: makeInput(), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["place", "climb", "weather"],
                       "cap 3, spec priority order: place(1) > climb(5) > weather(6) > question(8) > speech(9)")
    }

    func testEngine_themeNamedAtRankOne_neverReappearsAtLowerRank() {
        let firing: [DossierSenses.Sense: DossierSenses.SenseLine] = [
            .placeResonance: .init(text: "place move", lemma: "move"),
            .climbAnchoring: .init(text: "climb move", lemma: "move"),
            .speechShape: .init(text: "speech", lemma: nil)
        ]
        let output = DossierSenses.lines(input: makeInput(), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["place move", "speech"],
                       "the engine enforces one-theme-one-line even against a misbehaving sense")
    }

    func testEngine_nothingFiring_emitsNothing() {
        let output = DossierSenses.lines(input: makeInput(), evaluate: { _, _, _ in nil })
        XCTAssertTrue(output.lines.isEmpty)
        XCTAssertNil(output.reportedLunationIndex)
    }

    func testEngine_moonLineAdmitted_reportsLunationIndex() {
        let moon = DossierSenses.MoonInput(
            lunationIndex: 300, moonName: "Sturgeon Moon",
            start: DateFactory.makeDate(2024, 5, 8), end: DateFactory.makeDate(2024, 6, 6),
            lastReportedIndex: nil, currentWalkHasWords: true,
            allWalkDates: [], wordedWalkDates: []
        )
        let firing: [DossierSenses.Sense: DossierSenses.SenseLine] = [
            .moonLine: .init(text: "moon", lemma: nil)
        ]
        let output = DossierSenses.lines(input: makeInput(moon: moon), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["moon"])
        XCTAssertEqual(output.reportedLunationIndex, 300)
    }

    func testEngine_moonLineNotAdmitted_doesNotReport() {
        let output = DossierSenses.lines(input: makeInput(moon: nil), evaluate: { _, _, _ in nil })
        XCTAssertNil(output.reportedLunationIndex)
    }

    // MARK: - Helpers

    func testCoordinateHygiene_gates() {
        XCTAssertTrue(DossierSenses.qualifies(fix(lat: 0, lon: 0, accuracy: 99, gap: 90)))
        XCTAssertFalse(DossierSenses.qualifies(fix(lat: 0, lon: 0, accuracy: 100, gap: 5)),
                       "accuracy must be strictly under 100 m — LocationManagement's discipline")
        XCTAssertFalse(DossierSenses.qualifies(fix(lat: 0, lon: 0, accuracy: 10, gap: 91)),
                       "a stale sample (>90 s) never anchors a claim")
    }

    func testDistance_greatCircle() {
        let a = DossierSenses.Coordinate(latitude: 42.8782, longitude: -8.5448)
        let b = DossierSenses.Coordinate(latitude: 42.8791, longitude: -8.5448)
        XCTAssertEqual(DossierSenses.distance(a, b), 100, accuracy: 5)
    }

    func testMedian_oddAndEven() {
        XCTAssertEqual(DossierSenses.median([3, 1, 2]), 2)
        XCTAssertEqual(DossierSenses.median([1, 2, 3, 10]), 2.5)
    }

    func testNumberWords() {
        XCTAssertEqual(DossierSenses.timesPhrase(2), "twice")
        XCTAssertEqual(DossierSenses.timesPhrase(3), "three times")
        XCTAssertEqual(DossierSenses.timesPhrase(10), "10 times")
        XCTAssertEqual(DossierSenses.capitalizedCount(4), "Four")
        XCTAssertEqual(DossierSenses.capitalizedCount(11), "11")
        XCTAssertEqual(DossierSenses.ordinalWord(5), "Fifth")
        XCTAssertEqual(DossierSenses.ordinalWord(12), "Twelfth")
        XCTAssertEqual(DossierSenses.ordinalWord(13), "13th")
        XCTAssertEqual(DossierSenses.ordinalWord(21), "21st")
    }
}
