// UnitTests/CollectiveRouteCatalogTests.swift
import XCTest
@testable import Pilgrim

// MARK: - Fixtures

/// Ported from `../pilgrim-landing/js/collective-routes.test.js`.
///
/// Every vector pinned against this fixture is a property of THESE two routes,
/// not of the shipped seven-route artifact, whose weighted pool is roughly
/// twice the size and resolves the same dates differently. Asserting the web's
/// published numbers against the bundled artifact fails in a way that looks
/// exactly like a broken port.
///
/// Two adaptations from the JS source, neither behavioural: the routes gained
/// `"kind": "route"` (the web infers route-ness from the absence of `cosmic`)
/// and a `companyLine` (required by the entry model, read by no vector here).
private let fixtureJSON = Data("""
{
  "version": "fixture",
  "pilgrimages": [
    { "id": "kumano-kodo", "kind": "route", "nameEn": "Kumano Kodo", "companyLine": "K walked it.", "km": 39, "bestMonths": [3,4,5,10,11], "peakMonths": [4,5,10,11] },
    { "id": "camino-frances", "kind": "route", "nameEn": "Camino Francés", "companyLine": "F walked it.", "km": 764, "bestMonths": [5,6,9,10], "peakMonths": [7,8] }
  ],
  "horizons": [
    { "id": "around-earth", "kind": "cosmic", "preposition": "around", "body": "the Earth", "companyLine": "A handful have.", "km": 40075 },
    { "id": "to-the-moon", "kind": "cosmic", "preposition": "to", "body": "the Moon", "companyLine": "No one has.", "km": 384400 },
    { "id": "to-the-sun", "kind": "cosmic", "preposition": "to", "body": "the Sun", "companyLine": "No one ever will.", "km": 149600000 }
  ]
}
""".utf8)

/// The shipped artifact at `../pilgrim-landing/assets/collective-routes.json`
/// with `reflections` and `annual` stripped — iOS decodes neither of them.
private let productionJSON = Data("""
{
  "version": "0faeb638520c",
  "pilgrimages": [
    { "id": "camino-frances", "kind": "route", "nameEn": "Camino de Santiago", "companyLine": "242,179 pilgrims completed it in 2025.", "km": 764, "bestMonths": [5,6,9], "peakMonths": [7,8] },
    { "id": "camino-ingles", "kind": "route", "nameEn": "Camino Inglés", "companyLine": "30,204 pilgrims completed it in 2025.", "km": 112, "bestMonths": [4,5,6,9,10], "peakMonths": [7,8] },
    { "id": "camino-norte", "kind": "route", "nameEn": "Camino del Norte", "companyLine": "21,521 pilgrims completed it in 2025.", "km": 784, "bestMonths": [5,6,9], "peakMonths": [7,8] },
    { "id": "camino-portugues", "kind": "route", "nameEn": "Camino Portugués", "companyLine": "100,839 pilgrims completed it in 2025.", "km": 243, "bestMonths": [4,5,6,9,10], "peakMonths": [7,8] },
    { "id": "camino-primitivo", "kind": "route", "nameEn": "Camino Primitivo", "companyLine": "27,871 pilgrims completed it in 2025.", "km": 263, "bestMonths": [5,6,9], "peakMonths": [7,8] },
    { "id": "kumano-kodo", "kind": "route", "nameEn": "Kumano Kodo", "companyLine": "44,540 foreign visitors stayed overnight near Hongu in 2024.", "km": 39, "bestMonths": [3,4,5,10,11], "peakMonths": [4,5,10,11] },
    { "id": "shikoku-88", "kind": "route", "nameEn": "Shikoku 88 Temple Pilgrimage", "companyLine": "About 150,000 made the circuit in 2025; 1,622 on foot.", "km": 1200, "bestMonths": [3,4,5,10,11], "peakMonths": [4,10] }
  ],
  "horizons": [
    { "id": "around-earth", "kind": "cosmic", "preposition": "around", "body": "the Earth", "companyLine": "A handful have ever walked it; the first finished in 1974.", "km": 40075 },
    { "id": "to-the-moon", "kind": "cosmic", "preposition": "to", "body": "the Moon", "companyLine": "No one has ever walked it.", "km": 384400 },
    { "id": "to-the-sun", "kind": "cosmic", "preposition": "to", "body": "the Sun", "companyLine": "No one ever will.", "km": 149600000 }
  ]
}
""".utf8)

private func decodeCatalog(_ data: Data) throws -> CollectiveRouteCatalog {
    try JSONDecoder().decode(CollectiveRouteCatalog.self, from: data)
}

/// Wraps bare entry literals in the artifact's envelope.
private func catalogJSON(routes: String = "", horizons: String = "") -> Data {
    Data("{ \"version\": \"v\", \"pilgrimages\": [\(routes)], \"horizons\": [\(horizons)] }".utf8)
}

private func makeRoute(_ nameEn: String, km: Double, best: [Int] = [], peak: [Int] = [], id: String = "route-id") -> CollectiveRoute {
    CollectiveRoute(id: id, kind: .route(nameEn: nameEn), km: km, companyLine: "Some walked it.", bestMonths: best, peakMonths: peak)
}

private func makeHorizon(_ preposition: String, _ body: String, km: Double, id: String = "horizon-id") -> CollectiveRoute {
    CollectiveRoute(id: id, kind: .cosmic(preposition: preposition, body: body), km: km, companyLine: "No one has.")
}

// MARK: - Decoding

final class CollectiveRouteCatalogDecodingTests: XCTestCase {

    func testDecode_readsBothArraysIntoOneEntryList() throws {
        let catalog = try decodeCatalog(fixtureJSON)
        XCTAssertEqual(catalog.version, "fixture")
        XCTAssertEqual(catalog.entries.count, 5)
    }

    func testDecode_ordersRoutesByIdThenAppendsHorizonsInArtifactOrder() throws {
        XCTAssertEqual(try decodeCatalog(fixtureJSON).entries.map(\.id), ["camino-frances", "kumano-kodo", "around-earth", "to-the-moon", "to-the-sun"])
    }

    func testDecode_bindsRouteAndCosmicPayloads() throws {
        let catalog = try decodeCatalog(fixtureJSON)
        XCTAssertEqual(catalog.entries.first?.kind, .route(nameEn: "Camino Francés"))
        XCTAssertEqual(catalog.entries.last?.kind, .cosmic(preposition: "to", body: "the Sun"))
    }

    func testDecode_dropsEntryWithUnrecognisedKind() throws {
        let catalog = try decodeCatalog(catalogJSON(
            routes: """
            { "id": "good", "kind": "route", "nameEn": "Good", "companyLine": "c", "km": 10 },
            { "id": "weird", "kind": "wormhole", "nameEn": "Weird", "companyLine": "c", "km": 20 }
            """,
            horizons: """
            { "id": "around-earth", "kind": "cosmic", "preposition": "around", "body": "the Earth", "companyLine": "c", "km": 40075 }
            """
        ))

        XCTAssertEqual(catalog.entries.map(\.id), ["good", "around-earth"])
        XCTAssertNotNil(catalog.entry(for: DateFactory.makeDate(2026, 10, 7)), "Surviving entries must still select after a sibling is dropped")
    }

    func testDecode_dropsEntryMissingItsDistance() throws {
        let catalog = try decodeCatalog(catalogJSON(routes: """
        { "id": "good", "kind": "route", "nameEn": "Good", "companyLine": "c", "km": 10 },
        { "id": "no-km", "kind": "route", "nameEn": "No Distance", "companyLine": "c" }
        """))
        XCTAssertEqual(catalog.entries.map(\.id), ["good"])
    }

    // A zero-length entry divides by zero in the phrasing and then traps on the
    // Int conversion, so it is rejected at the boundary, not at every call site.
    func testDecode_dropsEntryWithNonPositiveDistance() throws {
        let catalog = try decodeCatalog(catalogJSON(routes: """
        { "id": "good", "kind": "route", "nameEn": "Good", "companyLine": "c", "km": 10 },
        { "id": "zero", "kind": "route", "nameEn": "Zero", "companyLine": "c", "km": 0 },
        { "id": "negative", "kind": "route", "nameEn": "Negative", "companyLine": "c", "km": -5 }
        """))
        XCTAssertEqual(catalog.entries.map(\.id), ["good"])
    }

    func testDecode_dropsRouteMissingItsName() throws {
        let catalog = try decodeCatalog(catalogJSON(routes: """
        { "id": "good", "kind": "route", "nameEn": "Good", "companyLine": "c", "km": 10 },
        { "id": "nameless", "kind": "route", "companyLine": "c", "km": 20 }
        """))
        XCTAssertEqual(catalog.entries.map(\.id), ["good"])
    }

    func testDecode_dropsEntryMissingItsCompanyLine() throws {
        let catalog = try decodeCatalog(catalogJSON(routes: """
        { "id": "good", "kind": "route", "nameEn": "Good", "companyLine": "c", "km": 10 },
        { "id": "silent", "kind": "route", "nameEn": "Silent", "km": 20 }
        """))
        XCTAssertEqual(catalog.entries.map(\.id), ["good"], "An entry with nobody to name cannot satisfy the walk-summary line")
    }

    func testDecode_treatsAbsentSeasonArraysAsNoSeasonality() throws {
        let json = catalogJSON(routes: """
        { "id": "sparse", "kind": "route", "nameEn": "Sparse", "companyLine": "c", "km": 100 }
        """)
        let entry = try XCTUnwrap(decodeCatalog(json).entries.first)
        XCTAssertEqual(entry.bestMonths, [])
        XCTAssertEqual(entry.peakMonths, [])
    }

    func testDecode_survivesAMissingHorizonsArray() throws {
        let json = Data("""
        { "version": "v", "pilgrimages": [ { "id": "a", "kind": "route", "nameEn": "A", "companyLine": "c", "km": 10 } ] }
        """.utf8)
        XCTAssertEqual(try decodeCatalog(json).entries.count, 1)
    }

    func testEmpty_hasNoEntries() {
        XCTAssertTrue(CollectiveRouteCatalog.empty.entries.isEmpty)
    }
}

// MARK: - Seeding

final class CollectiveRouteSeedTests: XCTestCase {

    func testUtcSeed_packsTheUtcCalendarDate() {
        XCTAssertEqual(CollectiveRouteSeed.utcSeed(for: DateFactory.makeDate(2026, 10, 7)), 20_261_007)
    }

    func testUtcSeed_ignoresTheTimeOfDay() {
        XCTAssertEqual(CollectiveRouteSeed.utcSeed(for: DateFactory.makeDate(2026, 10, 7, 23, 59, 59)), 20_261_007)
    }

    // Pinned against the web's fmix32 scramble. Any drift here reshuffles every
    // pilgrim's day and desyncs iOS from the site.
    func testHash_matchesTheWebScramble() {
        XCTAssertEqual(CollectiveRouteSeed.hash(20_261_007), 3_837_869_072)
        XCTAssertEqual(CollectiveRouteSeed.hash(20_260_101), 1_575_279_303)
        XCTAssertEqual(CollectiveRouteSeed.hash(1), 824_515_495)
        XCTAssertEqual(CollectiveRouteSeed.hash(0), 0)
        XCTAssertEqual(CollectiveRouteSeed.hash(4_294_967_295), 539_527_247)
    }
}

// MARK: - Seasonal weighting

final class CollectiveRouteWeightingTests: XCTestCase {

    private let kumano = makeRoute("Kumano Kodo", km: 39, best: [3, 4, 5, 10, 11], peak: [4, 5, 10, 11])
    private let camino = makeRoute("Camino", km: 700, best: [5, 6, 9], peak: [7, 8])

    func testWeight_bestAndPeakMonth_takesBothBonuses() {
        XCTAssertEqual(kumano.weight(inMonth: 10), 6)
    }

    func testWeight_offSeasonMonth_takesNeitherBonus() {
        XCTAssertEqual(kumano.weight(inMonth: 7), 1)
    }

    func testWeight_bestButNotPeakMonth_takesOnlyTheSeasonBonus() {
        XCTAssertEqual(camino.weight(inMonth: 5), 3)
    }

    // The peak bonus is an intensifier on being in season, never a boost of its
    // own. July is peak for the Camino and deliberately confers nothing.
    func testWeight_peakButNotBestMonth_takesNoBonusAtAll() {
        XCTAssertEqual(camino.weight(inMonth: 7), 1)
    }

    func testWeight_entryWithNoSeasonality_staysAtBase() {
        XCTAssertEqual(makeRoute("Sparse", km: 100).weight(inMonth: 7), 1)
    }

    func testWeight_cosmicHorizon_isConstantAcrossTheYear() {
        let earth = makeHorizon("around", "the Earth", km: 40_075)
        XCTAssertEqual(earth.weight(inMonth: 10), 1)
        XCTAssertEqual(earth.weight(inMonth: 1), 1)
    }
}

// MARK: - Selection

final class CollectiveRouteSelectionTests: XCTestCase {

    private var fixture: CollectiveRouteCatalog!

    override func setUpWithError() throws {
        fixture = try decodeCatalog(fixtureJSON)
    }

    // The web's named daily pick. Fixture-bound: the shipped artifact resolves
    // this date to camino-primitivo.
    func testEntryForDate_reproducesTheWebsPinnedFixtureVector() {
        XCTAssertEqual(fixture.entry(for: DateFactory.makeDate(2026, 10, 7))?.id, "kumano-kodo")
    }

    // The web's distribution assertion, over days 1–30 as its own loop runs
    // them. Fixture-bound: the shipped artifact yields 21 of 31.
    func testEntryForDate_octoberFavoursInSeasonRoutes() {
        let inSeason = (1...30).filter { day in
            fixture.entry(for: DateFactory.makeDate(2026, 10, day))?.bestMonths.contains(10) ?? false
        }
        XCTAssertEqual(inSeason.count, 26)
    }

    func testEntryForDate_isStableAcrossRepeatedCalls() {
        let date = DateFactory.makeDate(2026, 10, 7)
        let first = fixture.entry(for: date)?.id
        XCTAssertEqual(first, fixture.entry(for: date)?.id)
        XCTAssertEqual(first, fixture.entry(for: date)?.id)
    }

    // Midnight and one second to midnight UTC straddle the local-day boundary
    // in every time zone on earth, so agreeing here means no local calendar
    // leaked into the seed.
    func testEntryForDate_agreesAcrossTheWholeUtcDay() {
        let dayStart = DateFactory.makeDate(2026, 10, 7, 0, 0, 0)
        let dayEnd = DateFactory.makeDate(2026, 10, 7, 23, 59, 59)
        XCTAssertEqual(fixture.entry(for: dayStart)?.id, fixture.entry(for: dayEnd)?.id)
    }

    func testEntryForDate_reorderingTheRoutesDoesNotChangeTheSelection() {
        let routes = fixture.entries.filter { !$0.isCosmic }
        let horizons = fixture.entries.filter(\.isCosmic)
        let reordered = CollectiveRouteCatalog(version: "fixture", entries: Array(routes.reversed()) + horizons)

        for day in 1...31 {
            let date = DateFactory.makeDate(2026, 10, day)
            XCTAssertEqual(reordered.entry(for: date)?.id, fixture.entry(for: date)?.id, "on day \(day)")
        }
    }

    // The asymmetry is deliberate and ported: routes are sorted, horizons keep
    // artifact order. A curator who reorders the horizons moves everyone's day.
    func testCanonicallyOrdered_keepsHorizonsInTheOrderGiven() {
        let moon = makeHorizon("to", "the Moon", km: 384_400, id: "to-the-moon")
        let earth = makeHorizon("around", "the Earth", km: 40_075, id: "around-earth")
        XCTAssertEqual(CollectiveRouteCatalog.canonicallyOrdered([moon, earth]).map(\.id), ["to-the-moon", "around-earth"])
    }

    func testEntryForDate_emptyCatalog_returnsNothing() {
        XCTAssertNil(CollectiveRouteCatalog.empty.entry(for: DateFactory.makeDate(2026, 10, 7)))
    }

    func testEntryForDate_horizonsOnlyCatalog_stillSelects() {
        let catalog = CollectiveRouteCatalog(version: "v", entries: [
            makeHorizon("around", "the Earth", km: 40_075, id: "around-earth"),
            makeHorizon("to", "the Moon", km: 384_400, id: "to-the-moon")
        ])
        let picked = (1...31).compactMap { catalog.entry(for: DateFactory.makeDate(2026, 10, $0))?.id }
        XCTAssertEqual(picked.count, 31)
        XCTAssertTrue(Set(picked).isSubset(of: ["around-earth", "to-the-moon"]))
    }
}

// MARK: - Phrasing

final class CollectiveRoutePhrasingTests: XCTestCase {

    private let kumano = makeRoute("Kumano Kodo", km: 39)
    private let frances = makeRoute("Camino Francés", km: 764)
    private let earth = makeHorizon("around", "the Earth", km: 40_075)
    private let moon = makeHorizon("to", "the Moon", km: 384_400)
    private let sun = makeHorizon("to", "the Sun", km: 149_600_000)

    override func setUp() {
        super.setUp()
        UserPreferences.distanceMeasurementType.value = .kilometers
    }

    override func tearDown() {
        UserPreferences.distanceMeasurementType.delete()
        super.tearDown()
    }

    // The collective total is unknown until a counter fetch has ever landed.
    // Saying "the path is beginning" then would be a fabrication — the
    // collective is several hundred kilometres in.
    func testDailyLine_unknownTotal_saysNothing() {
        XCTAssertNil(kumano.dailyLine(collectiveKm: nil))
    }

    func testDailyLine_zeroTotal_saysThePathIsBeginning() {
        XCTAssertEqual(kumano.dailyLine(collectiveKm: 0), "The path is beginning.")
    }

    func testDailyLine_routeWalkedManyTimes_countsTheCompletions() {
        XCTAssertEqual(kumano.dailyLine(collectiveKm: 694.5), "Together, we've walked the Kumano Kodo 17 times.")
    }

    func testDailyLine_routeWalkedOnce_saysOneComplete() {
        XCTAssertEqual(makeRoute("Test Route", km: 500).dailyLine(collectiveKm: 694.5), "Together, one Test Route complete.")
    }

    func testDailyLine_routeNotYetReached_statesAPercentage() {
        XCTAssertEqual(frances.dailyLine(collectiveKm: 694.5), "We are 91% of the way to one Camino Francés.")
    }

    func testDailyLine_routeAlmostReached_clampsBelowOneHundredPercent() {
        XCTAssertEqual(makeRoute("Near Route", km: 700).dailyLine(collectiveKm: 699), "We are 99% of the way to one Near Route.")
    }

    func testDailyLine_horizonReachedTwice_countsTheCircuits() {
        XCTAssertEqual(earth.dailyLine(collectiveKm: 90_000), "Together, 2 times around the Earth.")
    }

    func testDailyLine_horizonReachedExactlyOnce_saysOnce() {
        XCTAssertEqual(earth.dailyLine(collectiveKm: 40_075), "Together, once around the Earth.")
    }

    func testDailyLine_horizonAtOrAboveOnePercent_statesOneDecimal() {
        XCTAssertEqual(earth.dailyLine(collectiveKm: 694.5), "We are 1.7% of the way around the Earth.")
    }

    func testDailyLine_horizonBelowOnePercent_statesTheRemainingDistance() {
        XCTAssertEqual(moon.dailyLine(collectiveKm: 694.5), "383,706 km to the Moon.")
        XCTAssertEqual(sun.dailyLine(collectiveKm: 694.5), "149,599,306 km to the Sun.")
    }

    // The only phrasing branch that states a raw distance, and so the only one
    // that has to honour the pilgrim's unit.
    func testDailyLine_horizonBelowOnePercent_rendersInMilesWhenPreferred() {
        UserPreferences.distanceMeasurementType.value = .miles
        XCTAssertEqual(moon.dailyLine(collectiveKm: 694.5), "238,424 mi to the Moon.")
    }

    func testDailyLine_nonFiniteTotal_saysThePathIsBeginning() {
        XCTAssertEqual(kumano.dailyLine(collectiveKm: .infinity), "The path is beginning.")
        XCTAssertEqual(kumano.dailyLine(collectiveKm: .nan), "The path is beginning.")
    }
}

// MARK: - Contribution phrasing

final class CollectiveRouteContributionTests: XCTestCase {

    private let norte = CollectiveRoute(id: "camino-norte", kind: .route(nameEn: "Camino del Norte"), km: 784, companyLine: "21,521 pilgrims completed it in 2025.")
    private let earth = CollectiveRoute(id: "around-earth", kind: .cosmic(preposition: "around", body: "the Earth"), km: 40_075, companyLine: "A handful have ever walked it; the first finished in 1974.")

    override func setUp() {
        super.setUp()
        UserPreferences.distanceMeasurementType.value = .kilometers
    }

    override func tearDown() {
        UserPreferences.distanceMeasurementType.delete()
        super.tearDown()
    }

    func testContributionLine_route_placesTheWalkAgainstItAndNamesItsCompany() {
        XCTAssertEqual(norte.contributionLine(walkKm: 4.2), "Your 4.2 km against the Camino del Norte. 21,521 pilgrims completed it in 2025.")
    }

    // A horizon has no name a pilgrim would recognise, so its magnitude carries
    // the contrast instead.
    func testContributionLine_horizon_statesTheHorizonsMagnitude() {
        XCTAssertEqual(earth.contributionLine(walkKm: 4.2), "Your 4.2 km against 40,075 km around the Earth. A handful have ever walked it; the first finished in 1974.")
    }

    func testContributionLine_horizonDay_isNeverSkipped() throws {
        let catalog = try decodeCatalog(productionJSON)
        let horizonDay = DateFactory.makeDate(2026, 10, 12)
        XCTAssertEqual(catalog.entry(for: horizonDay)?.id, "around-earth")
        XCTAssertNotNil(catalog.contributionLine(for: horizonDay, walkKm: 4.2))
    }

    func testContributionLine_respectsThePilgrimsUnit() {
        UserPreferences.distanceMeasurementType.value = .miles
        XCTAssertEqual(norte.contributionLine(walkKm: 4.2), "Your 2.6 mi against the Camino del Norte. 21,521 pilgrims completed it in 2025.")
    }

    func testContributionLine_emptyCatalog_saysNothing() {
        XCTAssertNil(CollectiveRouteCatalog.empty.contributionLine(for: DateFactory.makeDate(2026, 10, 7), walkKm: 4.2))
    }
}

// MARK: - Parity with the web module

/// Generated by running `../pilgrim-landing/js/collective-routes.js` over the
/// shipped artifact — one entry id per UTC day, in order. October carries the
/// seasonal bonuses; January is fully off-season, which is the only way the
/// sub-one-percent horizon branch comes up often enough to be worth checking.
private let webPicks: [(year: Int, month: Int, ids: String)] = [
    (2026, 10, "kumano-kodo,camino-primitivo,kumano-kodo,camino-primitivo,camino-ingles,shikoku-88,camino-primitivo,shikoku-88,kumano-kodo,shikoku-88,camino-primitivo,around-earth,shikoku-88,camino-portugues,kumano-kodo,shikoku-88,shikoku-88,camino-portugues,kumano-kodo,camino-primitivo,camino-ingles,camino-frances,shikoku-88,camino-primitivo,camino-portugues,camino-ingles,camino-portugues,camino-primitivo,around-earth,kumano-kodo,kumano-kodo"),
    (2027, 1, "camino-primitivo,around-earth,camino-primitivo,kumano-kodo,camino-norte,to-the-sun,kumano-kodo,kumano-kodo,shikoku-88,to-the-sun,camino-norte,camino-portugues,shikoku-88,camino-norte,camino-frances,around-earth,camino-norte,camino-portugues,kumano-kodo,shikoku-88,camino-portugues,camino-ingles,camino-ingles,shikoku-88,camino-frances,to-the-moon,camino-ingles,camino-ingles,to-the-sun,camino-primitivo,to-the-moon")
]

/// The line the web renders for each entry at a collective total of 696.98 km.
private let webLines: [String: String] = [
    "around-earth": "We are 1.7% of the way around the Earth.",
    "camino-frances": "We are 91% of the way to one Camino de Santiago.",
    "camino-ingles": "Together, we've walked the Camino Inglés 6 times.",
    "camino-norte": "We are 89% of the way to one Camino del Norte.",
    "camino-portugues": "Together, we've walked the Camino Portugués 2 times.",
    "camino-primitivo": "Together, we've walked the Camino Primitivo 2 times.",
    "kumano-kodo": "Together, we've walked the Kumano Kodo 17 times.",
    "shikoku-88": "We are 58% of the way to one Shikoku 88 Temple Pilgrimage.",
    "to-the-moon": "383,703 km to the Moon.",
    "to-the-sun": "149,599,303 km to the Sun."
]

final class CollectiveRouteWebParityTests: XCTestCase {

    private static let collectiveKm = 696.98
    private var production: CollectiveRouteCatalog!

    override func setUpWithError() throws {
        production = try decodeCatalog(productionJSON)
        UserPreferences.distanceMeasurementType.value = .kilometers
    }

    override func tearDown() {
        UserPreferences.distanceMeasurementType.delete()
        super.tearDown()
    }

    private func eachWebPick(_ check: (Date, String, String) -> Void) {
        for month in webPicks {
            for (index, expectedId) in month.ids.split(separator: ",").enumerated() {
                let day = index + 1
                check(DateFactory.makeDate(month.year, month.month, day),
                      String(expectedId),
                      "on \(month.year)-\(month.month)-\(day)")
            }
        }
    }

    func testEntryForDate_agreesWithTheWebEveryDayOfTwoSampleMonths() {
        eachWebPick { date, expectedId, label in
            XCTAssertEqual(production.entry(for: date)?.id, expectedId, label)
        }
    }

    func testDailyLine_agreesWithTheWebEveryDayOfTwoSampleMonths() {
        eachWebPick { date, expectedId, label in
            XCTAssertEqual(production.dailyLine(for: date, collectiveKm: Self.collectiveKm), webLines[expectedId], label)
        }
    }

    func testEntryForDate_productionCatalogDivergesFromTheWebsFixtureVector() {
        XCTAssertEqual(production.entry(for: DateFactory.makeDate(2026, 10, 7))?.id, "camino-primitivo", "The published 'kumano-kodo' vector belongs to the two-route test fixture, not this artifact")
    }

    func testEntryForDate_octoberFavoursInSeasonRoutes() {
        let inSeason = (1...31).filter { day in
            production.entry(for: DateFactory.makeDate(2026, 10, day))?.bestMonths.contains(10) ?? false
        }
        XCTAssertEqual(inSeason.count, 21)
    }

    // Determinism alone would be satisfied by returning the same entry forever.
    // The scramble is what stops consecutive days walking one weighted block.
    func testEntryForDate_consecutiveDaysScatter() {
        let month = (1...31).compactMap { production.entry(for: DateFactory.makeDate(2026, 10, $0))?.id }
        let changes = zip(month, month.dropFirst()).filter { $0 != $1 }.count
        XCTAssertGreaterThanOrEqual(changes, 20, "Consecutive days should rarely repeat")
        XCTAssertGreaterThanOrEqual(Set(month).count, 5, "A month should surface several different entries")
    }
}
