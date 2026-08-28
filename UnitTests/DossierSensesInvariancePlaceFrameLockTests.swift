import XCTest
@testable import Pilgrim

/// Signal 4 (place-frame lock): the same theme spoken inside the same
/// `DossierSenses.placeClusterRadius` cluster every time its location was
/// known, across the in-window walks the fixes themselves come from.
/// New file, not an addition to `DossierSensesInvarianceTests.swift` — the
/// parent sits at 458 lines, close enough to the `file_length` warning gate
/// of 500 that this signal's fixture-heavy tests (each needs its own
/// `fixes` dictionary) would push it over. Same split pattern as
/// `DossierSensesInvarianceFrameConstancyCoverageTests.swift`: an
/// `extension DossierSensesInvarianceTests` sharing the parent's
/// `steadyThread` and `modalInput` fixtures (already internal, not
/// private, from the Task 5 split).
extension DossierSensesInvarianceTests {

    private static let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)

    /// Production shape, not a convenience: every appearance carries a
    /// recording instant inside `ThreadStore.recurrenceWindow` and an
    /// English-analyzed context. `ThreadsDossierBuilder.resolveFixes` only
    /// resolves a route fix for an in-window recording, so an appearance with
    /// no timestamp is one the locator was never offered — and a fixture that
    /// left `recordingTimestamps` empty could not see the window gate at all.
    /// Appearances are placed a day apart, newest first, unless a test hands
    /// in its own `timestamps`.
    private func fixInput(
        threads: [WalkThread], fixes: [UUID: DossierSenses.RouteFix],
        timestamps: [UUID: Date]? = nil, languageCode: String? = "en"
    ) -> DossierSenses.Input {
        let appearances = threads.flatMap(\.appearances)
        let resolved = timestamps ?? Dictionary(
            uniqueKeysWithValues: appearances.enumerated().map { offset, appearance in
                (appearance.recordingUUID, Self.walkStart.addingTimeInterval(-Double(offset + 1) * 86400))
            }
        )
        return DossierSenses.Input(
            currentWalkUUID: UUID(),
            walkStart: Self.walkStart,
            walkEnd: Self.walkStart.addingTimeInterval(5400),
            totalAscent: 0, elevationSeries: [], photos: [], currentRecordings: [],
            historicalContexts: appearances.map {
                plainContext($0.recordingUUID, languageCode: languageCode)
            },
            threads: threads, backfillComplete: true,
            walkSnapshots: [], recordingTimestamps: resolved, fixes: fixes, moon: nil
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
            "Every time 'river' was spoken with its location known, it was in the same place "
                + "— on all 3 of its walks in the last 30 days."
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

    /// The full-coverage requirement was relaxed (product decision,
    /// 2026-08-27): this app runs on rural pilgrimage routes where GPS
    /// coverage is uneven, and demanding every appearance-walk contribute a
    /// fix meant one dead-zone walk could permanently silence an otherwise
    /// genuinely place-locked theme. 4 walks total, 3 with qualifying fixes
    /// that cluster tightly, the 4th walk's only recording has no fix at
    /// all (never attempted a route fix) — the signal now speaks, but the
    /// sentence must tell the truth about what was measured: "3 of its 4
    /// walks in the last 30 days", not "all 4".
    func testPlaceFrameLock_oneWalkWithNoFixAtAll_rendersMeasuredCoverage() {
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
        let line = DossierSensesInvariance.placeFrameLock(
            input: fixInput(threads: [thread], fixes: fixes), suppressed: []
        )
        XCTAssertEqual(
            line?.text,
            "Every time 'river' was spoken with its location known, it was in the same place "
                + "— on 3 of its 4 walks in the last 30 days."
        )
        XCTAssertEqual(line?.lemma, "river")
    }

    /// A walk enters the measured set on its FIRST qualifying fix, but a
    /// theme can be spoken twice on one walk — here walkA's second utterance
    /// has no fix at all, 5km of nothing between what was measured and what
    /// was claimed. The old wording ("spoken in the same place on all N
    /// walks it appears in") vouched for that second utterance; the shipped
    /// wording scopes itself to located utterances, which is exactly the set
    /// `maxPairwiseSpread` judged. Requiring every appearance to carry a fix
    /// instead would be stricter than the walk-level full-coverage check the
    /// 2026-08-27 product decision deliberately removed for rural routes.
    func testPlaceFrameLock_secondUnlocatedUtteranceOnAMeasuredWalk_claimsOnlyWhatWasMeasured() {
        let recs = [UUID(), UUID(), UUID(), UUID()]
        let walkA = UUID(), walkB = UUID(), walkC = UUID()
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for offset in 0..<3 {
            fixes[recs[offset]] = qualifyingFix(
                .init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12)
            )
        }
        // recs[3] is a second utterance on walkA with no fix at all — it
        // could have been anywhere, and nothing here ever looked.
        let thread = steadyThread("river", recordings: recs, walks: [walkA, walkB, walkC, walkA])
        let line = DossierSensesInvariance.placeFrameLock(
            input: fixInput(threads: [thread], fixes: fixes), suppressed: []
        )
        XCTAssertEqual(
            line?.text,
            "Every time 'river' was spoken with its location known, it was in the same place "
                + "— on all 3 of its walks in the last 30 days."
        )
        XCTAssertFalse(line?.text.contains("has been spoken in the same place on all") ?? true,
                       "the sentence must not vouch for an utterance nothing measured")
    }

    /// Below the `minimumInvariantWalks` floor is judged on the MEASURED
    /// count, not the appearance count — a theme appearing on many walks
    /// with only a couple of usable fixes must stay silent, because
    /// clustering over fewer than 3 points is not evidence of anything,
    /// no matter how large the theme's full walk-set is.
    func testPlaceFrameLock_measuredWalksBelowMinimum_staysSilentDespiteManyAppearances() {
        let recs = (0..<10).map { _ in UUID() }
        let walks = (0..<10).map { _ in UUID() }
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for offset in 0..<2 {
            fixes[recs[offset]] = qualifyingFix(
                .init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12)
            )
        }
        // recs[2...9] intentionally have no entry in `fixes`.
        let thread = steadyThread("river", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes), suppressed: []
            )
        )
    }

    /// The claim's denominator must come from the same window the fixes come
    /// from. `ThreadsDossierBuilder.resolveFixes` resolves a route fix only
    /// for an appearance whose recording instant falls inside
    /// `ThreadStore.recurrenceWindow`, so eleven appearances from six months
    /// ago were never offered to the locator at all — counting them made the
    /// sentence read "on 3 of the 14 walks it appears in" under an opening
    /// clause that vouches for every located utterance. Three in-window
    /// walks, all located, all clustered: the honest reading is "all 3 of its
    /// walks in the last 30 days".
    func testPlaceFrameLock_appearancesOutsideTheFixWindow_areNotInTheDenominator() {
        let recent = [UUID(), UUID(), UUID()]
        let ancient = (0..<11).map { _ in UUID() }
        let recentWalks = [UUID(), UUID(), UUID()]
        let ancientWalks = (0..<11).map { _ in UUID() }
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recent.enumerated() {
            fixes[rec] = qualifyingFix(.init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12))
        }
        var timestamps: [UUID: Date] = [:]
        for (offset, rec) in recent.enumerated() {
            timestamps[rec] = Self.walkStart.addingTimeInterval(-Double(offset + 1) * 86400)
        }
        // Six months back: real walks at real logged places, but far outside
        // the window `resolveFixes` will ever look in.
        for (offset, rec) in ancient.enumerated() {
            timestamps[rec] = Self.walkStart.addingTimeInterval(-Double(offset + 100) * 86400)
        }
        let thread = steadyThread(
            "river", recordings: recent + ancient, walks: recentWalks + ancientWalks
        )
        let line = DossierSensesInvariance.placeFrameLock(
            input: fixInput(threads: [thread], fixes: fixes, timestamps: timestamps), suppressed: []
        )
        XCTAssertEqual(
            line?.text,
            "Every time 'river' was spoken with its location known, it was in the same place "
                + "— on all 3 of its walks in the last 30 days."
        )
        XCTAssertFalse(line?.text.contains("14") ?? true,
                       "the unwindowed appearance history is not a denominator this signal can see")
    }

    /// `fusedThemes` and `placeFrameLock` read only themes and coordinates,
    /// so nothing gated them by language the way a `MarkerPack` read gates
    /// the other three. `TranscriptNLP.contentLemmaMentions` falls back to
    /// the lowercased surface form wherever NLTagger has no lemma model, and
    /// this app's walkers cross the Camino in French, German, Italian,
    /// Portuguese and Spanish — where two inflections of one word become two
    /// themes and a place-lock claim rests on a token that was never
    /// lemmatized. Same fixture as `testPlaceFrameLock_sameCluster_fires`,
    /// analyzed as French: silent.
    func testPlaceFrameLock_nonEnglishRecordings_staySilent() {
        let recs = [UUID(), UUID(), UUID()]
        let walks = [UUID(), UUID(), UUID()]
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for (offset, rec) in recs.enumerated() {
            fixes[rec] = qualifyingFix(.init(latitude: 51.5 + Double(offset) * 0.0001, longitude: -0.12))
        }
        let thread = steadyThread("riviere", recordings: recs, walks: walks)
        XCTAssertNil(
            DossierSensesInvariance.placeFrameLock(
                input: fixInput(threads: [thread], fixes: fixes, languageCode: "fr"), suppressed: []
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
