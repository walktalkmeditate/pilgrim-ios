import XCTest
@testable import Pilgrim

final class ReleasedThreadsPackageTests: XCTestCase {

    private let released = DateFactory.makeDate(2026, 8, 20, 9, 0, 0)

    private func preferences(
        releasedThreads: [PilgrimReleasedThread]?,
        welcomedBack: [PilgrimWelcomedBackThread]? = nil
    ) -> PilgrimPreferences {
        PilgrimPreferences(
            distanceUnit: "km", altitudeUnit: "m", speedUnit: "km/h", energyUnit: "kJ",
            celestialAwareness: false, zodiacSystem: "tropical", beginWithIntention: false,
            releasedThreads: releasedThreads,
            welcomedBackThreads: welcomedBack
        )
    }

    func testPreferences_roundTripWithReleasedThreads() throws {
        let original = preferences(
            releasedThreads: [
                PilgrimReleasedThread(term: "the move", lemmas: ["move", "moving"], releasedAt: released)
            ],
            welcomedBack: [
                PilgrimWelcomedBackThread(term: "father", welcomedBackAt: released)
            ]
        )
        let data = try PilgrimDateCoding.makeEncoder().encode(original)
        let decoded = try PilgrimDateCoding.makeDecoder().decode(PilgrimPreferences.self, from: data)
        XCTAssertEqual(decoded.releasedThreads?.count, 1)
        XCTAssertEqual(decoded.releasedThreads?[0].term, "the move")
        XCTAssertEqual(decoded.releasedThreads?[0].lemmas, ["move", "moving"])
        XCTAssertEqual(decoded.releasedThreads?[0].releasedAt, released)
        XCTAssertEqual(decoded.welcomedBackThreads?.map(\.term), ["father"])
        XCTAssertEqual(decoded.welcomedBackThreads?.first?.welcomedBackAt, released)
    }

    func testPreferences_oldJSONWithoutKey_decodesNil() throws {
        let old = """
        {"distanceUnit":"km","altitudeUnit":"m","speedUnit":"km/h","energyUnit":"kJ",
        "celestialAwareness":false,"zodiacSystem":"tropical","beginWithIntention":false}
        """
        let decoded = try PilgrimDateCoding.makeDecoder()
            .decode(PilgrimPreferences.self, from: Data(old.utf8))
        XCTAssertNil(decoded.releasedThreads)
        XCTAssertNil(decoded.welcomedBackThreads)
    }

    func testBuildManifest_mapsReleasedThreads() {
        let manifest = PilgrimPackageConverter.buildManifest(
            walkCount: 0, events: [],
            releasedThreads: [ReleasedThread(displayTerm: "the move", lemmas: ["move"], releasedAt: released)],
            welcomedBackThreads: [WelcomedBackThread(displayTerm: "father", welcomedBackAt: released)]
        )
        XCTAssertEqual(manifest.preferences.releasedThreads?.map(\.term), ["the move"])
        XCTAssertEqual(manifest.preferences.releasedThreads?.first?.releasedAt, released)
        XCTAssertEqual(manifest.preferences.welcomedBackThreads?.map(\.term), ["father"])
    }

    func testBuildManifest_emptyReleasedSet_omitsKey() throws {
        let manifest = PilgrimPackageConverter.buildManifest(
            walkCount: 0, events: [], releasedThreads: [], welcomedBackThreads: []
        )
        XCTAssertNil(manifest.preferences.releasedThreads)
        XCTAssertNil(manifest.preferences.welcomedBackThreads)
        let json = String(decoding: try PilgrimDateCoding.makeEncoder().encode(manifest), as: UTF8.self)
        XCTAssertFalse(json.contains("releasedThreads"),
                       "a walker who released nothing exports a byte-identical preferences block")
        XCTAssertFalse(json.contains("welcomedBackThreads"))
    }

    func testImportMapping_fromPreferences() {
        let mapped = PilgrimPackageConverter.releasedThreads(from: preferences(releasedThreads: [
            PilgrimReleasedThread(term: "father", lemmas: ["father"], releasedAt: released)
        ]))
        XCTAssertEqual(mapped, [
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        ])
        XCTAssertEqual(PilgrimPackageConverter.releasedThreads(from: preferences(releasedThreads: nil)), [])
        XCTAssertEqual(
            PilgrimPackageConverter.welcomedBackThreads(from: preferences(
                releasedThreads: nil,
                welcomedBack: [PilgrimWelcomedBackThread(term: "father", welcomedBackAt: released)]
            )),
            [WelcomedBackThread(displayTerm: "father", welcomedBackAt: released)]
        )
        XCTAssertEqual(PilgrimPackageConverter.welcomedBackThreads(from: preferences(releasedThreads: nil)), [])
    }

    func testImportMapping_futureDatedDecisions_clampToNow() {
        let now = released
        let future = released.addingTimeInterval(365 * 86400)

        let mappedReleased = PilgrimPackageConverter.releasedThreads(
            from: preferences(releasedThreads: [
                PilgrimReleasedThread(term: "father", lemmas: ["father"], releasedAt: future)
            ]),
            now: now
        )
        XCTAssertEqual(mappedReleased, [
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: now)
        ], "a clock-skewed exporting device must not win every future merge — clamp to import time")

        let mappedWelcomedBack = PilgrimPackageConverter.welcomedBackThreads(
            from: preferences(
                releasedThreads: nil,
                welcomedBack: [PilgrimWelcomedBackThread(term: "father", welcomedBackAt: future)]
            ),
            now: now
        )
        XCTAssertEqual(mappedWelcomedBack, [
            WelcomedBackThread(displayTerm: "father", welcomedBackAt: now)
        ])
    }

    func testImportMapping_futureDatedRelease_laterLocalDecisionStillWins() throws {
        let suiteName = "ReleasedThreadsPackageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReleasedThreadsStore(defaults: defaults)

        let now = released
        let future = released.addingTimeInterval(365 * 86400)
        let clampedImport = PilgrimPackageConverter.releasedThreads(
            from: preferences(releasedThreads: [
                PilgrimReleasedThread(term: "father", lemmas: ["father"], releasedAt: future)
            ]),
            now: now
        )
        store.merge(released: clampedImport, welcomedBack: [])

        // A genuine later decision must still be able to win. Had the skewed
        // future date been allowed to stand uncapped, this entirely ordinary
        // later release would have lost to a date a year away, forever.
        let later = now.addingTimeInterval(60)
        store.merge(released: [
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: later)
        ], welcomedBack: [])

        XCTAssertEqual(store.all.first?.releasedAt, later,
                       "a later, unskewed decision must be able to win — the clamp keeps the earlier import from parking a permanent future date")
    }
}
