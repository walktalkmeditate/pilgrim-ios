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
        recordingTimestamps: [UUID: Date] = [:],
        fixes: [UUID: DossierSenses.RouteFix] = [:],
        moon: DossierSenses.MoonInput? = nil
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: currentWalkUUID, walkStart: walkStart, walkEnd: walkEnd,
            totalAscent: totalAscent, elevationSeries: elevationSeries, photos: photos,
            currentRecordings: currentRecordings, threads: threads,
            backfillComplete: backfillComplete, walkSnapshots: walkSnapshots,
            recordingTimestamps: recordingTimestamps, fixes: fixes, moon: moon
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
            .photoAdjacency: .init(text: "photo", lemma: "trail"),
            .weatherWeave: .init(text: "weather", lemma: "music")
        ]
        let output = DossierSenses.lines(input: makeInput(), evaluate: stub(firing))
        XCTAssertEqual(output.lines, ["place", "climb", "weather"],
                       "cap 3, spec priority order: place(1) > climb(5) > weather(6) > photo(7) > speech(8) " +
                       "(questionDensity cut at the ship gate — the enum now has 8 cases, not 9)")
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
        XCTAssertEqual(DossierSenses.ordinalWord(5), "Fifth")
        XCTAssertEqual(DossierSenses.ordinalWord(12), "Twelfth")
        XCTAssertEqual(DossierSenses.ordinalWord(13), "13th")
        XCTAssertEqual(DossierSenses.ordinalWord(21), "21st")
    }

    // MARK: - Climb anchoring fixtures

    func thread(lemma: String, display: String? = nil, appearances: [ThreadAppearance]) -> WalkThread {
        WalkThread(lemma: lemma, displayTerm: display ?? lemma, appearances: appearances)
    }

    func appearance(recording: UUID = UUID(), walk: UUID, date: Date, mentions: Int = 2) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: 0.02)
    }

    func currentRecording(
        uuid: UUID = UUID(), start: Date, end: Date, text: String = "words",
        wordCount: Int = 40, themeLemmas: [String] = []
    ) -> DossierSenses.CurrentRecording {
        DossierSenses.CurrentRecording(
            uuid: uuid, start: start, end: end, text: text, wordCount: wordCount,
            themes: themeLemmas.map {
                Theme(lemma: $0, displayTerm: $0, mentionCount: 2, salience: 0.05,
                      mentions: [ThemeMention(start: 0, length: 4)])
            }
        )
    }

    /// 40 min of flat, 10 min climbing 60 m, 40 min flat — one unmistakable
    /// steepest sustained ascent in the middle.
    func hillSeries(start: Date) -> [DossierSenses.ElevationSample] {
        var samples: [DossierSenses.ElevationSample] = []
        for i in 0..<240 {  // 10 s cadence, 40 min
            samples.append(.init(timestamp: start.addingTimeInterval(Double(i) * 10), altitude: 100))
        }
        for i in 0..<60 {   // 10 min, +1 m per 10 s
            samples.append(.init(timestamp: start.addingTimeInterval(2400 + Double(i) * 10),
                                 altitude: 100 + Double(i)))
        }
        for i in 0..<240 {
            samples.append(.init(timestamp: start.addingTimeInterval(3000 + Double(i) * 10), altitude: 160))
        }
        return samples
    }

    func testClimb_mentionOnSteepestClimb_fires() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            walkEnd: start.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(2500),
                end: start.addingTimeInterval(2700), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move", display: "the move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertEqual(
            DossierSenses.climbAnchoring(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "'the move' was spoken on the day's steepest climb.", lemma: "move")
        )
    }

    func testClimb_mentionOnTheFlat_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            walkEnd: start.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(300),
                end: start.addingTimeInterval(500), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertNil(DossierSenses.climbAnchoring(input: input, suppressed: []))
    }

    func testClimb_flatWalkUnder50mAscent_skipsEntirely() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            totalAscent: 49,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(2500),
                end: start.addingTimeInterval(2700), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertNil(DossierSenses.climbAnchoring(input: input, suppressed: []),
                     "total ascent < 50 m makes the claim meaningless — binding skip")
    }

    func testClimb_jitterWithoutSustainedGain_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let start = Self.walkStart
        // ±3 m sawtooth: raw gradients spike, smoothed sustained gain never
        // reaches 20 m — the smoothing exists exactly for this.
        let series = (0..<540).map { i in
            DossierSenses.ElevationSample(
                timestamp: start.addingTimeInterval(Double(i) * 10),
                altitude: 100 + Double(i % 2) * 3
            )
        }
        let input = makeInput(
            currentWalkUUID: walkUUID,
            totalAscent: 60,
            elevationSeries: series,
            currentRecordings: [currentRecording(
                uuid: recUUID, start: start.addingTimeInterval(2500),
                end: start.addingTimeInterval(2700), themeLemmas: ["move"]
            )],
            threads: [thread(lemma: "move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: start)])]
        )
        XCTAssertNil(DossierSenses.climbAnchoring(input: input, suppressed: []))
    }

    func testClimb_suppressedTheme_fallsThroughToNextTheme() {
        let walkUUID = UUID()
        let recA = UUID(), recB = UUID()
        let start = Self.walkStart
        let input = makeInput(
            currentWalkUUID: walkUUID,
            walkEnd: start.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: hillSeries(start: start),
            currentRecordings: [
                currentRecording(uuid: recA, start: start.addingTimeInterval(2500),
                                 end: start.addingTimeInterval(2600), themeLemmas: ["move"]),
                currentRecording(uuid: recB, start: start.addingTimeInterval(2600),
                                 end: start.addingTimeInterval(2700), themeLemmas: ["river"])
            ],
            threads: [
                thread(lemma: "move", appearances: [appearance(recording: recA, walk: walkUUID, date: start)]),
                thread(lemma: "river", appearances: [appearance(recording: recB, walk: walkUUID, date: start)])
            ]
        )
        let line = DossierSenses.climbAnchoring(input: input, suppressed: ["move"])
        XCTAssertEqual(line?.lemma, "river")
    }

    // MARK: - Speech shape

    func testSpeechShape_wordsInFirstThird_longWordlessRemainder_fires() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(7200)  // 2 h walk; first third ends at 40 min
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600)),
                currentRecording(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(1500))
            ]
        )
        XCTAssertEqual(
            DossierSenses.speechShape(input: input, suppressed: []),
            DossierSenses.SenseLine(
                text: "All the words came in the first third; the last 95 minutes were wordless.",
                lemma: nil
            )
        )
    }

    func testSpeechShape_lateRecording_doesNotFire() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(7200)
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600)),
                currentRecording(start: start.addingTimeInterval(3000), end: start.addingTimeInterval(3300))
            ]
        )
        XCTAssertNil(DossierSenses.speechShape(input: input, suppressed: []))
    }

    func testSpeechShape_shortWordlessRemainder_doesNotFire() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(2700)  // 45 min walk
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(60), end: start.addingTimeInterval(900))
            ]
        )
        XCTAssertNil(DossierSenses.speechShape(input: input, suppressed: []),
                     "1800 s remainder must EXCEED 30 minutes, not merely reach it")
    }

    func testSpeechShape_wordlessRecordings_doNotAnchorTheClaim() {
        let start = Self.walkStart
        let end = start.addingTimeInterval(7200)
        let input = makeInput(
            walkStart: start, walkEnd: end,
            currentRecordings: [
                currentRecording(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600)),
                currentRecording(start: start.addingTimeInterval(5000), end: start.addingTimeInterval(5100),
                                 wordCount: 0)
            ]
        )
        XCTAssertNotNil(DossierSenses.speechShape(input: input, suppressed: []),
                        "a zero-word recording is not words — it cannot break the first-third claim")
    }
}
