import XCTest
@testable import Pilgrim

final class DossierSensesCrossWalkTests: XCTestCase {

    static let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
    static let walkEnd = DateFactory.makeDate(2024, 6, 15, 10, 30, 0)

    func makeInput(
        currentWalkUUID: UUID = UUID(),
        walkStart: Date = DossierSensesCrossWalkTests.walkStart,
        walkEnd: Date = DossierSensesCrossWalkTests.walkEnd,
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

    func thread(lemma: String, display: String? = nil, appearances: [ThreadAppearance]) -> WalkThread {
        WalkThread(lemma: lemma, displayTerm: display ?? lemma, appearances: appearances)
    }

    func appearance(recording: UUID = UUID(), walk: UUID, date: Date, mentions: Int = 2) -> ThreadAppearance {
        ThreadAppearance(recordingUUID: recording, walkUUID: walk, date: date,
                         mentionCount: mentions, salience: 0.02)
    }

    func snapshotRow(
        walk: UUID = UUID(), date: Date, intention: String? = nil, weather: String? = nil
    ) -> DossierSenses.WalkSnapshotRow {
        DossierSenses.WalkSnapshotRow(walkUUID: walk, startDate: date,
                                      intention: intention, weatherCondition: weather)
    }

    // MARK: - Weather buckets

    func testWeatherBucket_everyStorableConditionMapsToAKnownBucket() {
        for condition in WeatherCondition.allCases {
            XCTAssertNotEqual(DossierSenses.bucket(forStoredCondition: condition.rawValue), .unknown,
                              "\(condition.rawValue) fell out of the bucket map — WeatherKit vocabulary drifted")
        }
    }

    func testWeatherBucket_unrecognizedStringLandsInUnknown() {
        XCTAssertEqual(DossierSenses.bucket(forStoredCondition: "Rain"), .unknown,
                       "REST conditionCodes are mapped before storage; a raw one must not pass as rain")
    }

    // MARK: - Weather weave

    private func weaveInput(
        themeWalkWeather: [String?], otherWalkWeather: [String?]
    ) -> DossierSenses.Input {
        let currentWalk = UUID()
        var snapshots: [DossierSenses.WalkSnapshotRow] = []
        var appearances: [ThreadAppearance] = []
        for (i, weather) in themeWalkWeather.enumerated() {
            let walkUUID = i == 0 ? currentWalk : UUID()
            let date = Self.walkStart.addingTimeInterval(Double(i) * -3 * 86400)
            snapshots.append(snapshotRow(walk: walkUUID, date: date, weather: weather))
            appearances.append(appearance(walk: walkUUID, date: date))
        }
        for (i, weather) in otherWalkWeather.enumerated() {
            snapshots.append(snapshotRow(
                walk: UUID(), date: Self.walkStart.addingTimeInterval(Double(i + 1) * -5 * 86400),
                weather: weather
            ))
        }
        return makeInput(
            currentWalkUUID: currentWalk,
            threads: [thread(lemma: "music", appearances: appearances)],
            walkSnapshots: snapshots
        )
    }

    func testWeatherWeave_sharedMinorityCondition_fires() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain"],
                               otherWalkWeather: ["clear", "clear", "clear"])
        XCTAssertEqual(
            DossierSenses.weatherWeave(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "Both walks where 'music' surfaced were under rain.", lemma: "music")
        )
    }

    func testWeatherWeave_threeWalks_usesAllPhrasing() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain", "thunderstorm"],
                               otherWalkWeather: ["clear", "clear", "clear", "clear"])
        XCTAssertEqual(DossierSenses.weatherWeave(input: input, suppressed: [])?.text,
                       "All 3 walks where 'music' surfaced were under rain.")
    }

    func testWeatherWeave_climateGuard_majorityConditionSuppresses() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain"],
                               otherWalkWeather: ["lightRain", "lightRain"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []),
                     "in a place where it mostly rains, 'both walks under rain' is geography, not signal")
    }

    func testWeatherWeave_anyExcludedWalk_emitsNothing() {
        let input = weaveInput(themeWalkWeather: ["lightRain", nil],
                               otherWalkWeather: ["clear", "clear", "clear"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []),
                     "the claim must be total — a walk without stored weather voids it")
    }

    func testWeatherWeave_mixedConditions_doesNotFire() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "snow"],
                               otherWalkWeather: ["clear", "clear", "clear"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []))
    }

    func testWeatherWeave_singleWalkTheme_doesNotFire() {
        let input = weaveInput(themeWalkWeather: ["lightRain"],
                               otherWalkWeather: ["clear", "clear"])
        XCTAssertNil(DossierSenses.weatherWeave(input: input, suppressed: []))
    }

    func testWeatherWeave_pluralityWithoutMajority_doesNotSuppress() {
        let input = weaveInput(themeWalkWeather: ["lightRain", "heavyRain"],
                               otherWalkWeather: ["clear", "clear", "snow"])
        XCTAssertEqual(
            DossierSenses.weatherWeave(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "Both walks where 'music' surfaced were under rain.", lemma: "music")
        )
    }

    // MARK: - Place-theme resonance

    /// Theme 'music' spoken at the river bend on two walks; theme 'work'
    /// spoken kilometers apart — the wide baseline the guard divides by.
    private func placeInput(
        clusterOffsetMeters: Double = 40,
        baselineSpreadDegrees: Double = 0.05,   // ~5.5 km — wide daily range
        backfillComplete: Bool = true,
        secondClusterFixGap: TimeInterval = 5
    ) -> DossierSenses.Input {
        let currentWalk = UUID(), otherWalk = UUID()
        let recA = UUID(), recB = UUID(), farC = UUID(), farD = UUID()
        let dayA = Self.walkStart, dayB = Self.walkStart.addingTimeInterval(-5 * 86400)
        let timestamps: [UUID: Date] = [
            recA: dayA.addingTimeInterval(600), recB: dayB.addingTimeInterval(600),
            farC: dayA.addingTimeInterval(1200), farD: dayB.addingTimeInterval(1200)
        ]
        let latOffset = clusterOffsetMeters / 111_320
        let fixes: [UUID: DossierSenses.RouteFix] = [
            recA: fix(lat: 42.8782, lon: -8.5448),
            recB: fix(lat: 42.8782 + latOffset, lon: -8.5448, gap: secondClusterFixGap),
            farC: fix(lat: 42.8782 + baselineSpreadDegrees, lon: -8.5448),
            farD: fix(lat: 42.8782 - baselineSpreadDegrees, lon: -8.5448)
        ]
        let threads = [
            thread(lemma: "music", appearances: [
                appearance(recording: recA, walk: currentWalk, date: dayA, mentions: 2),
                appearance(recording: recB, walk: otherWalk, date: dayB, mentions: 1)
            ]),
            thread(lemma: "work", appearances: [
                appearance(recording: farC, walk: currentWalk, date: dayA),
                appearance(recording: farD, walk: otherWalk, date: dayB)
            ])
        ]
        return makeInput(
            currentWalkUUID: currentWalk,
            threads: threads,
            backfillComplete: backfillComplete,
            recordingTimestamps: timestamps,
            fixes: fixes
        )
    }

    func testPlace_tightClusterWideBaseline_fires() {
        XCTAssertEqual(
            DossierSenses.placeResonance(input: placeInput(), suppressed: []),
            DossierSenses.SenseLine(
                text: "'music' has surfaced on 2 walks — 3 times near the same stretch of ground.",
                lemma: "music"
            )
        )
    }

    func testPlace_twoMentionCluster_saysTwice() {
        let currentWalk = UUID(), otherWalk = UUID()
        let recA = UUID(), recB = UUID(), farC = UUID(), farD = UUID()
        let dayA = Self.walkStart, dayB = Self.walkStart.addingTimeInterval(-5 * 86400)
        let input = makeInput(
            currentWalkUUID: currentWalk,
            threads: [
                thread(lemma: "music", appearances: [
                    appearance(recording: recA, walk: currentWalk, date: dayA, mentions: 1),
                    appearance(recording: recB, walk: otherWalk, date: dayB, mentions: 1)
                ]),
                thread(lemma: "work", appearances: [
                    appearance(recording: farC, walk: currentWalk, date: dayA),
                    appearance(recording: farD, walk: otherWalk, date: dayB)
                ])
            ],
            recordingTimestamps: [
                recA: dayA.addingTimeInterval(600), recB: dayB.addingTimeInterval(600),
                farC: dayA.addingTimeInterval(1200), farD: dayB.addingTimeInterval(1200)
            ],
            fixes: [
                recA: fix(lat: 42.8782, lon: -8.5448),
                recB: fix(lat: 42.87824, lon: -8.5448),
                farC: fix(lat: 42.93, lon: -8.5448),
                farD: fix(lat: 42.82, lon: -8.5448)
            ]
        )
        XCTAssertEqual(DossierSenses.placeResonance(input: input, suppressed: [])?.text,
                       "'music' has surfaced on 2 walks — twice near the same stretch of ground.")
    }

    func testPlace_specificityGuard_tightBaselineSuppresses() {
        let input = placeInput(baselineSpreadDegrees: 0.0005)  // ~55 m daily loop
        XCTAssertNil(DossierSenses.placeResonance(input: input, suppressed: []),
                     "when ALL recordings cluster, a 150 m match means nothing — routine geography suppresses")
    }

    func testPlace_backfillIncomplete_suppresses() {
        XCTAssertNil(DossierSenses.placeResonance(input: placeInput(backfillComplete: false), suppressed: []),
                     "an origin-class claim waits on the backfill gate")
    }

    func testPlace_hygieneFailedFix_dropsRecordingFromCluster() {
        XCTAssertNotNil(DossierSenses.placeResonance(input: placeInput(), suppressed: []))
        XCTAssertNil(DossierSenses.placeResonance(input: placeInput(secondClusterFixGap: 120), suppressed: []),
                     "a stale fix drops its recording; one walk's mentions alone cannot cluster")
    }

    func testPlace_singleWalkCluster_doesNotFire() {
        let currentWalk = UUID()
        let recA = UUID(), recB = UUID(), farC = UUID()
        let dayA = Self.walkStart
        let input = makeInput(
            currentWalkUUID: currentWalk,
            threads: [
                thread(lemma: "music", appearances: [
                    appearance(recording: recA, walk: currentWalk, date: dayA, mentions: 2),
                    appearance(recording: recB, walk: currentWalk, date: dayA, mentions: 2)
                ]),
                thread(lemma: "work", appearances: [appearance(recording: farC, walk: currentWalk, date: dayA)])
            ],
            recordingTimestamps: [recA: dayA.addingTimeInterval(60), recB: dayA.addingTimeInterval(900),
                                  farC: dayA.addingTimeInterval(1500)],
            fixes: [recA: fix(lat: 42.8782, lon: -8.5448), recB: fix(lat: 42.87824, lon: -8.5448),
                    farC: fix(lat: 42.93, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.placeResonance(input: input, suppressed: []),
                     "≥2 distinct walks — one walk's cluster is a walk, not a resonance")
    }

    func testPlace_onlyFirstFourActiveThreadsChecked() {
        let base = placeInput()
        // Push 'music' past the candidate cap with four alphabetically-earlier
        // active threads carrying no cluster of their own.
        let fillers = ["alpha", "beta", "delta", "gamma"].map { name in
            thread(lemma: name, appearances: [appearance(walk: base.currentWalkUUID, date: Self.walkStart)])
        }
        let input = makeInput(
            currentWalkUUID: base.currentWalkUUID,
            threads: (fillers + base.threads).sorted { $0.lemma < $1.lemma },
            recordingTimestamps: base.recordingTimestamps,
            fixes: base.fixes
        )
        XCTAssertNil(DossierSenses.placeResonance(input: input, suppressed: []),
                     "cost bound: only the thread section's first 4 themes are checked")
    }

    // MARK: - Intention lineage

    private func lineageInput(intentions: [String?], todayIntention: String?) -> DossierSenses.Input {
        let currentWalk = UUID()
        var snapshots = [snapshotRow(walk: currentWalk, date: Self.walkStart, intention: todayIntention)]
        for (i, intention) in intentions.enumerated() {
            snapshots.append(snapshotRow(
                walk: UUID(), date: Self.walkStart.addingTimeInterval(Double(i + 1) * -3 * 86400),
                intention: intention
            ))
        }
        return makeInput(currentWalkUUID: currentWalk, walkSnapshots: snapshots)
    }

    func testLineage_sharedContentLemmaAcrossFiveWalks_firesWithOrdinal() {
        let input = lineageInput(
            intentions: ["release the day", "releasing my grip", "release what is done", "release again"],
            todayIntention: "release what I cannot carry"
        )
        XCTAssertEqual(
            DossierSenses.intentionLineage(input: input, suppressed: []),
            DossierSenses.SenseLine(
                text: "Fifth walk in the last 30 days carrying some form of 'release'.",
                lemma: "release"
            )
        )
    }

    func testLineage_scaffoldOnlyOverlap_mustNotCluster() {
        let input = lineageInput(
            intentions: ["want to call my mother", "want less noise around meals"],
            todayIntention: "want a slower morning"
        )
        XCTAssertNil(DossierSenses.intentionLineage(input: input, suppressed: []),
                     "the spec's required fixture: unrelated intentions sharing only 'want' must NOT cluster")
    }

    func testLineage_twoPriorWalks_belowFloor() {
        let input = lineageInput(intentions: ["release the day"], todayIntention: "release the morning")
        XCTAssertNil(DossierSenses.intentionLineage(input: input, suppressed: []),
                     "≥3 in-window walks carrying the family — two is coincidence")
    }

    func testLineage_todayWithoutIntentionInFamily_doesNotFire() {
        let input = lineageInput(
            intentions: ["release the day", "releasing my grip", "release what is done"],
            todayIntention: "walk with the river"
        )
        XCTAssertNil(DossierSenses.intentionLineage(input: input, suppressed: []))
    }

    // MARK: - Question density

    private func questionInput(today: String, history: [String]) -> DossierSenses.Input {
        let currentWalk = UUID()
        let recUUID = UUID()
        var walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [:]
        var timestamps: [UUID: Date] = [:]
        var transcripts: [(recordingUUID: UUID, transcript: String)] = []
        for (i, text) in history.enumerated() {
            let historyRec = UUID()
            let date = Self.walkStart.addingTimeInterval(Double(i + 1) * -3 * 86400)
            walkIndex[historyRec] = (UUID(), date)
            timestamps[historyRec] = date.addingTimeInterval(600)
            transcripts.append((historyRec, text))
        }
        return makeInput(
            currentWalkUUID: currentWalk,
            currentRecordings: [DossierSenses.CurrentRecording(
                uuid: recUUID, start: Self.walkStart, end: Self.walkStart.addingTimeInterval(300),
                text: today, wordCount: TranscriptNLP.wordCount(in: today), themes: []
            )],
            historyTranscripts: transcripts,
            recordingTimestamps: timestamps,
            walkIndex: walkIndex
        )
    }

    func testQuestionDensity_todayDoublesTheMedianAndTopsEveryWalk_fires() {
        let input = questionInput(
            today: "Who sits with him? What changes? Why now? What am I holding?",
            history: ["A question? Another?", "One thing today?", "No questions today at all."]
        )
        XCTAssertEqual(
            DossierSenses.questionDensity(input: input, suppressed: []),
            DossierSenses.SenseLine(
                text: "Four of today's sentences were questions — more than any walk in the last 30 days.",
                lemma: nil
            )
        )
    }

    func testQuestionDensity_tiedWithAHistoryWalk_doesNotFire() {
        let input = questionInput(
            today: "Who? What? Why?",
            history: ["One? Two? Three?", "Quiet.", "Still quiet."]
        )
        XCTAssertNil(DossierSenses.questionDensity(input: input, suppressed: []),
                     "today must EXCEED every other in-window walk, not tie one")
    }

    func testQuestionDensity_underThreeQuestions_doesNotFire() {
        let input = questionInput(today: "Why now? What next?", history: ["Quiet.", "Quiet.", "Quiet."])
        XCTAssertNil(DossierSenses.questionDensity(input: input, suppressed: []))
    }

    func testQuestionDensity_underThreeHistoryWalks_doesNotFire() {
        let input = questionInput(today: "Who? What? Why?", history: ["Quiet.", "Quiet."])
        XCTAssertNil(DossierSenses.questionDensity(input: input, suppressed: []),
                     "≥3 walks of history required before a median means anything")
    }
}
