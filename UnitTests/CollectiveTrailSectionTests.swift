// UnitTests/CollectiveTrailSectionTests.swift
import XCTest
@testable import Pilgrim

// MARK: - Fixtures

/// The shipped artifact, trimmed to the fields iOS decodes. Selection is what
/// makes the date-anchor test meaningful, so the real weighted pool is used
/// rather than a two-entry stand-in.
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

// MARK: - The render gate

/// The gate is a pure function precisely so these live without a view, a
/// service, or a running app. The line's *content* belongs to
/// `CollectiveRouteCatalogTests`; what is owned here is whether it appears.
final class CollectiveTrailSectionGateTests: XCTestCase {

    private let walkDate = DateFactory.makeDate(2026, 10, 7)
    private var catalog: CollectiveRouteCatalog!
    private var line: String!

    override func setUpWithError() throws {
        UserPreferences.distanceMeasurementType.value = .kilometers
        catalog = try JSONDecoder().decode(CollectiveRouteCatalog.self, from: productionJSON)
        line = try XCTUnwrap(catalog.contributionLine(for: walkDate, walkKm: 4.2))
    }

    override func tearDown() {
        UserPreferences.distanceMeasurementType.delete()
        super.tearDown()
    }

    // AE1. A pilgrim who keeps their walks to themselves is told nothing about
    // a counter they never moved.
    func testGate_walkWasNotContributed_rendersNothing() {
        XCTAssertNil(CollectiveTrailSection.renderedLine(wasContributed: false, contributionLine: line))
    }

    func testGate_contributedWithALoadedCatalog_rendersTheLineUnchanged() {
        XCTAssertEqual(
            CollectiveTrailSection.renderedLine(wasContributed: true, contributionLine: line),
            line
        )
    }

    // The catalog is nil for the first frames of every summary — the load is
    // detached — and stays nil if the artifact failed to decode. Half a line is
    // worse than none.
    func testGate_catalogNotYetLoaded_rendersNothing() {
        let notLoaded: CollectiveRouteCatalog? = nil
        let resolved = notLoaded?.contributionLine(for: walkDate, walkKm: 4.2)
        XCTAssertNil(CollectiveTrailSection.renderedLine(wasContributed: true, contributionLine: resolved))
    }

    func testGate_emptyCatalog_rendersNothing() {
        let resolved = CollectiveRouteCatalog.empty.contributionLine(for: walkDate, walkKm: 4.2)
        XCTAssertNil(CollectiveTrailSection.renderedLine(wasContributed: true, contributionLine: resolved))
    }

    /// The plan left open whether an unknown collective total should suppress
    /// both surfaces. It suppresses only one: the Settings line states the
    /// collective's progress and cannot invent it, while this line states the
    /// walk's own distance against a fixed route length and never needs a
    /// total at all. That asymmetry is what lets a walk that ended on day
    /// twelve with no signal still say something true.
    func testGate_isIndependentOfTheCollectiveTotal() {
        XCTAssertNotNil(
            CollectiveTrailSection.renderedLine(wasContributed: true, contributionLine: line),
            "The walk-summary line must survive a collective total that never arrived"
        )
        XCTAssertNil(
            catalog.dailyLine(for: walkDate, collectiveKm: nil),
            "The Settings line is the surface that does suppress itself without a total"
        )
    }

    // AE6. The two callouts are gated on disjoint facts — the milestone on this
    // pilgrim's own history, the trail on whether the walk was sent — so a walk
    // that earns both shows both, stacked, rather than one displacing the other.
    func testGate_walkCrossingAPersonalMilestone_satisfiesBothGatesIndependently() {
        let personalMilestone: String? = "You've now walked 100 km total"

        XCTAssertNotNil(personalMilestone, "WalkSummaryView renders its milestone callout on this being non-nil")
        XCTAssertNotNil(
            CollectiveTrailSection.renderedLine(wasContributed: true, contributionLine: line),
            "and the trail renders beneath it on a condition that shares no input"
        )
    }
}

// MARK: - Date anchor

/// The summary is presented for any walk opened from the journal, not only for
/// one that just ended. Anchoring to `Date()` would hand an old walk a
/// different route every time it was reopened.
final class CollectiveTrailSectionDateAnchorTests: XCTestCase {

    private var catalog: CollectiveRouteCatalog!

    override func setUpWithError() throws {
        UserPreferences.distanceMeasurementType.value = .kilometers
        catalog = try JSONDecoder().decode(CollectiveRouteCatalog.self, from: productionJSON)
    }

    override func tearDown() {
        UserPreferences.distanceMeasurementType.delete()
        super.tearDown()
    }

    func testLine_resolvesTheWalksOwnUtcDayNotAnother() throws {
        let walkDay = DateFactory.makeDate(2026, 10, 7)
        let reopenedOn = DateFactory.makeDate(2026, 10, 12)

        // Pinned so a reshuffle of the selection cannot quietly turn this into
        // a comparison of one route against itself.
        XCTAssertEqual(catalog.entry(for: walkDay)?.id, "camino-primitivo")
        XCTAssertEqual(catalog.entry(for: reopenedOn)?.id, "around-earth")

        let walkDayLine = try XCTUnwrap(catalog.contributionLine(for: walkDay, walkKm: 4.2))
        XCTAssertTrue(walkDayLine.contains("Camino Primitivo"))
        XCTAssertNotEqual(walkDayLine, catalog.contributionLine(for: reopenedOn, walkKm: 4.2))
    }

    // Midnight and one second to midnight UTC straddle the local-day boundary
    // everywhere on earth, so agreeing across both means the walk's own UTC day
    // is what decides, whatever the pilgrim's time zone.
    func testLine_holdsAcrossTheWholeUtcDayOfTheWalk() {
        let dayStart = DateFactory.makeDate(2026, 10, 7, 0, 0, 0)
        let dayEnd = DateFactory.makeDate(2026, 10, 7, 23, 59, 59)
        XCTAssertEqual(
            catalog.contributionLine(for: dayStart, walkKm: 4.2),
            catalog.contributionLine(for: dayEnd, walkKm: 4.2)
        )
    }

    // The longest string the feature can produce, and the budget the section's
    // line limit and scale factor were sized against. Company sentences are
    // curator-editable after ship, so this is a tripwire rather than a fact.
    func testLine_longestPhrasingStaysWithinTheRenderBudget() throws {
        let longest = try XCTUnwrap(
            catalog.entries.map { $0.contributionLine(walkKm: 12.34) }.max(by: { $0.count < $1.count })
        )
        XCTAssertLessThanOrEqual(longest.count, 130, "Re-tune lineLimit and minimumScaleFactor before letting this grow")
    }
}

// MARK: - Contribution log

/// The gate's `wasContributed` input, which must be a record of what happened
/// rather than a reading of the current preference.
final class CollectiveContributionLogTests: XCTestCase {

    /// Spelled out rather than read off the type. If the storage contract
    /// moves, this should fail rather than follow it — a renamed key orphans
    /// every already-recorded walk on every installed device.
    private let storageKey = "collectiveContributedWalkUUIDs"
    private let suiteName = "CollectiveContributionLogTests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeLog() -> CollectiveContributionLog {
        CollectiveContributionLog(defaults: defaults)
    }

    func testWasContributed_unrecordedWalk_isFalse() {
        XCTAssertFalse(makeLog().wasContributed(walkUUID: "walk-1"))
    }

    func testRecord_survivesARoundTripThroughANewInstance() {
        makeLog().record(walkUUID: "walk-1")
        XCTAssertTrue(makeLog().wasContributed(walkUUID: "walk-1"))
    }

    func testRecord_doesNotVouchForWalksItNeverSaw() {
        let log = makeLog()
        log.record(walkUUID: "walk-1")
        XCTAssertFalse(log.wasContributed(walkUUID: "walk-2"))
    }

    func testRecord_isIdempotent() {
        let log = makeLog()
        log.record(walkUUID: "walk-1")
        log.record(walkUUID: "walk-1")
        XCTAssertEqual(defaults.array(forKey: storageKey) as? [String], ["walk-1"])
    }

    func testRecord_usesASingleKeyRatherThanOnePerWalk() {
        let log = makeLog()
        for index in 0..<20 { log.record(walkUUID: "walk-\(index)") }
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter { $0.contains("Contributed") }.count, 1)
    }

    // Unbounded growth in UserDefaults is its own bug. Seeded to the cap rather
    // than looped up to it so the test costs one write instead of a thousand.
    func testRecord_atCapacity_dropsTheOldestIdentifier() {
        let atCapacity = (0..<CollectiveContributionLog.capacity).map { "walk-\($0)" }
        defaults.set(atCapacity, forKey: storageKey)

        let log = makeLog()
        log.record(walkUUID: "walk-newest")

        XCTAssertEqual((defaults.array(forKey: storageKey) as? [String])?.count, CollectiveContributionLog.capacity)
        XCTAssertFalse(log.wasContributed(walkUUID: "walk-0"), "The oldest walk is the one that falls off")
        XCTAssertTrue(log.wasContributed(walkUUID: "walk-\(CollectiveContributionLog.capacity - 1)"))
        XCTAssertTrue(log.wasContributed(walkUUID: "walk-newest"))
    }

    // A re-record after a retry must not cost an unrelated walk its place.
    func testRecord_atCapacity_repeatingAKnownWalkEvictsNothing() {
        let atCapacity = (0..<CollectiveContributionLog.capacity).map { "walk-\($0)" }
        defaults.set(atCapacity, forKey: storageKey)

        let log = makeLog()
        log.record(walkUUID: "walk-500")

        XCTAssertEqual(defaults.array(forKey: storageKey) as? [String], atCapacity)
    }
}
