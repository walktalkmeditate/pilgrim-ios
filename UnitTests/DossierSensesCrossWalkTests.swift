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
}
