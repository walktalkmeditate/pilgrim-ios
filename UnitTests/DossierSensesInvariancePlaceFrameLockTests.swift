import XCTest
@testable import Pilgrim

/// Signal 4 (place-frame lock): the same theme spoken inside the same
/// `DossierSenses.placeClusterRadius` cluster on every walk it appears in.
/// New file, not an addition to `DossierSensesInvarianceTests.swift` — the
/// parent sits at 458 lines, close enough to the `file_length` warning gate
/// of 500 that this signal's fixture-heavy tests (each needs its own
/// `fixes` dictionary) would push it over. Same split pattern as
/// `DossierSensesInvarianceFrameConstancyCoverageTests.swift`: an
/// `extension DossierSensesInvarianceTests` sharing the parent's
/// `steadyThread` and `modalInput` fixtures (already internal, not
/// private, from the Task 5 split).
extension DossierSensesInvarianceTests {

    private func fixInput(
        threads: [WalkThread], fixes: [UUID: DossierSenses.RouteFix]
    ) -> DossierSenses.Input {
        DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            walkEnd: DateFactory.makeDate(2024, 6, 15, 10, 30, 0),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: [], threads: threads, backfillComplete: true,
            walkSnapshots: [], recordingTimestamps: [:], fixes: fixes, moon: nil
        )
    }

    private func qualifyingFix(_ coordinate: DossierSenses.Coordinate) -> DossierSenses.RouteFix {
        DossierSenses.RouteFix(coordinate: coordinate, horizontalAccuracy: 10, gapSeconds: 5)
    }

    /// Exact rendered string, not merely non-nil — the Task 3 lesson,
    /// replayed for this signal.
    func testPlaceFrameLock_sameCluster_fires() {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recs.enumerated() {
            fixes[rec] = qualifyingFix(.init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12))
        }
        let thread = steadyThread("river", recordings: recs, walks: walks)
        let line = DossierSensesInvariance.placeFrameLock(
            input: fixInput(threads: [thread], fixes: fixes), suppressed: []
        )
        XCTAssertEqual(
            line?.text,
            "'river' has been spoken in the same place on all 3 walks it appears in."
        )
        XCTAssertEqual(line?.lemma, "river")
    }

    func testPlaceFrameLock_scatteredFixes_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recs.enumerated() {
            fixes[rec] = qualifyingFix(.init(latitude: 51.5 + Double(offset) * 0.5, longitude: -0.12))
        }
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: []
            )
        )
    }

    func testPlaceFrameLock_poorAccuracyFixesExcluded_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for rec in recs {
            fixes[rec] = DossierSenses.RouteFix(
                coordinate: .init(latitude: 51.5, longitude: -0.12),
                horizontalAccuracy: 500, gapSeconds: 5
            )
        }
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: []
            )
        )
    }

    func testPlaceFrameLock_belowMinimumWalks_staysSilent() {
        let recs = [UUID(), UUID()]
        let walks = [UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for rec in recs {
            fixes[rec] = qualifyingFix(.init(latitude: 51.5, longitude: -0.12))
        }
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: []
            )
        )
    }

    func testPlaceFrameLock_suppressedLemma_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recs.enumerated() {
            fixes[rec] = qualifyingFix(.init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12))
        }
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: ["river"]
            )
        )
    }

    /// The overclaim this task was warned about, reproduced and pinned:
    /// 4 walks total, 3 with qualifying fixes that cluster tightly, the
    /// 4th walk's only recording has no fix at all (never attempted a
    /// route fix). The brief's original draft counted `Set(appearances
    /// .map(\.walkUUID)).count` over EVERY appearance regardless of fix
    /// quality — it would have rendered "on all 4 walks" while the
    /// clustering geometry only ever looked at 3. Shipped code requires
    /// full coverage (every walk in the theme's walk-set must contribute
    /// at least one qualifying fix) before it will speak at all.
    func testPlaceFrameLock_oneWalkWithNoFixAtAll_staysSilent() {
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for offset in 0..<3 {
            fixes[recs[offset]] = qualifyingFix(
                .init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12)
            )
        }
        // recs[3] / walks[3] intentionally has no entry in `fixes` — a
        // route fix that was never recorded, not merely a poor one.
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: []
            )
        )
    }

    /// The anchor-arbitrariness case the task flagged: three points where
    /// two of them sit ~130m from a shared "anchor" coordinate (each
    /// individually within `placeClusterRadius` of it) but ~260m from
    /// EACH OTHER — outside the 150m radius pairwise. An implementation
    /// that tests only "within radius of the first coordinate encountered"
    /// would fire here; the shipped implementation judges the full
    /// pairwise spread and must stay silent. Coordinates verified via
    /// haversine distance before writing this test: anchor-to-p1 and
    /// anchor-to-p2 ≈ 130m, p1-to-p2 ≈ 260m.
    func testPlaceFrameLock_pointsNearSharedAnchorButFarApart_staysSilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        let anchor = DossierSenses.Coordinate(latitude: 51.5, longitude: -0.12)
        let north = DossierSenses.Coordinate(latitude: 51.5 + 0.00117, longitude: -0.12)
        let south = DossierSenses.Coordinate(latitude: 51.5 - 0.00117, longitude: -0.12)
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        fixes[recs[0]] = qualifyingFix(anchor)
        fixes[recs[1]] = qualifyingFix(north)
        fixes[recs[2]] = qualifyingFix(south)
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: []
            )
        )
    }
}
