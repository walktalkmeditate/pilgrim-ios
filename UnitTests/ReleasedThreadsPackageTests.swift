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
}
