// UnitTests/CollectiveRouteBundledArtifactTests.swift
import XCTest
@testable import Pilgrim

/// What keeps the parity vectors honest.
///
/// Every vector in `CollectiveRouteCatalogTests` is pinned against
/// `collectiveParityFixtureJSON`, an inline transcription. The file the app
/// actually reads is `Pilgrim/Support Files/collective-routes-bootstrap.json`,
/// which `scripts/regen-route-bootstrap.sh` rewrites from a fresh bake. Nothing
/// forces the two to agree — so a re-bake that adds an eighth entry changes the
/// shipped pool, every date it resolves, and every line a pilgrim reads, while
/// all 62 vectors keep passing against a copy that no longer describes anything.
///
/// These compare only what selection consumes. Company sentences are
/// curator-editable by design and must be free to change without failing here;
/// ids, distances, seasons and provenance are not. The sentences have their own
/// guard in `testLine_longestPhrasingStaysWithinTheRenderBudget`, which measures
/// the bundled file for exactly this reason.
final class CollectiveRouteBundledArtifactTests: XCTestCase {

    private static let driftAdvice = """
        — the bundled artifact and collectiveParityFixtureJSON have diverged. \
        Every webPicks/webLines vector is generated from the fixture, so they now pin \
        a pool the app does not use. Re-generate the vectors from the new artifact \
        (../pilgrim-landing/js/collective-routes.js) and update the fixture together.
        """

    private var bundled: CollectiveRouteCatalog!
    private var fixture: CollectiveRouteCatalog!

    override func setUpWithError() throws {
        bundled = try BundledCollectiveArtifact.decoded()
        fixture = try decodeCatalog(collectiveParityFixtureJSON)
    }

    // The cheapest guard here: a bake that emits an envelope with nothing in it
    // decodes cleanly — both arrays are optional and every element decodes
    // lossily — so an empty catalog is not a decode failure. It would ship as a
    // silent, permanent absence of the line.
    func testBundledArtifact_decodesThroughTheProductionPathIntoEntries() throws {
        let catalog = try BundledCollectiveArtifact.decoded()

        XCTAssertFalse(catalog.entries.isEmpty, "The shipped bootstrap decoded to nothing — a bad bake reached the bundle")
        XCTAssertFalse(catalog.version.isEmpty, "The app compares versions to decide when to refresh")
    }

    func testBundledArtifact_selectsTheSameEntriesInTheSameOrderAsTheParityFixture() {
        XCTAssertEqual(bundled.entries.map(\.id), fixture.entries.map(\.id), Self.driftAdvice)
    }

    func testBundledArtifact_carriesTheSameDistancesAsTheParityFixture() {
        XCTAssertEqual(bundled.entries.map(\.km), fixture.entries.map(\.km), Self.driftAdvice)
    }

    // Weight is what a month's selection is built from, so a curator widening one
    // route's season re-resolves dates that route never claimed.
    func testBundledArtifact_carriesTheSameSeasonsAsTheParityFixture() {
        XCTAssertEqual(bundled.entries.map(\.bestMonths), fixture.entries.map(\.bestMonths), Self.driftAdvice)
        XCTAssertEqual(bundled.entries.map(\.peakMonths), fixture.entries.map(\.peakMonths), Self.driftAdvice)
    }

    // Which array an entry shipped in decides where it lands in the pool, and a
    // cosmic entry mis-filed among the pilgrimages splits iOS from the web
    // without either side complaining. `scripts/regen-route-bootstrap.sh` rejects
    // that upstream; this is the same guard standing over the file as bundled.
    func testBundledArtifact_filesEachEntryUnderTheSameKindAsTheParityFixture() {
        XCTAssertEqual(bundled.entries.map(\.isCosmic), fixture.entries.map(\.isCosmic), Self.driftAdvice)
    }
}
