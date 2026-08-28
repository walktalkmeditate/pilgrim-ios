import XCTest
@testable import Pilgrim

/// Review-fix coverage for how the `Noticed:` block is routed into the three
/// dossier variants — which senses reach which voice, and whether the block
/// reaches them at all.
///
/// The markerColoring leak: `Noticed:`'s
/// markerColoring sense is marker-derived commentary on the current walk's
/// speech, so it must be excluded from the same variants
/// `ThreadsDossierFormatter.dossier`'s `includeMarkerLines: false` already
/// excludes its own marker section from — otherwise a marker-suppressed
/// voice (Journaling) or a thread-analysis-suppressed voice (Creative,
/// Gratitude) would still read "Absolutist words cluster around 'X'" by a
/// side door. Split from `ThreadsDossierSensesTests.swift` to keep both
/// files under the `file_length` lint gate (same house rule as
/// `DossierSensesMarkerPhotoTests.swift`).
extension ThreadsDossierTests {

    /// "the move ... about the move" reliably becomes a real NLTagger noun
    /// theme (`ThemeExtractorTests.moveText` pins the same shape), and the
    /// four absolutist words sit right next to both mentions with nothing
    /// absolutist anywhere else — the filler carries no noun at all, so no
    /// theme other than "move" can ever compete for the dossier's one
    /// `Noticed:` slot.
    private func markerColoringTranscript() -> String {
        let prefix = "the move must always happen and everything about the move is completely certain now "
        let filler = "and it stayed calm and it did not shift much "
        return prefix + String(repeating: filler, count: 6)
    }

    private func markerColoringFixtureDossiers() -> (
        dossier: String?, unchangedBlock: String?, dossierWithoutMarkers: String?, dossierSensesOnly: String?
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierMarkerColoringLeakTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let defaults = UserDefaults(suiteName: "DossierMarkerColoringLeakTests-\(UUID().uuidString)")!

        let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let walkA = UUID(), recA = UUID()
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [recA: (walkA, walkStart)]
        let recording = RecordingContext(
            text: markerColoringTranscript(), timestamp: walkStart.addingTimeInterval(300),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: recA, endTimestamp: walkStart.addingTimeInterval(420)
        )
        // Pre-report this lunation so the moon line stays silent — this
        // fixture is isolating markerColoring, not an incidental second sense.
        let lunation = LunationCalendar.mostRecentClosed(asOf: walkStart)
        defaults.set(lunation.index, forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        let bundle = DossierSensesFetchBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            totalAscent: 0, elevationSeries: [], photos: [], walkSnapshots: [],
            recordingTimestamps: [recA: walkStart.addingTimeInterval(300)],
            closedLunation: lunation, moonName: LunationCalendar.moonName(for: lunation)
        )

        return ThreadsDossierBuilder.buildResult(
            walkUUID: walkA, recordings: [recording], walkIndex: walkIndex,
            store: store, senses: bundle, resolveRouteFix: { _ in nil }, defaults: defaults
        )
    }

    func testMarkerColoring_firesInFullDossier_absentFromMarkerFreeVariant() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let result = markerColoringFixtureDossiers()
        XCTAssertNotNil(result.dossier)
        XCTAssertTrue(result.dossier!.contains("Absolutist words cluster around"),
                      "the fixture must actually fire markerColoring, or this test proves nothing")
        XCTAssertNotNil(result.dossierWithoutMarkers)
        XCTAssertFalse(result.dossierWithoutMarkers!.contains("Absolutist words cluster around"),
                       "the marker-suppressed variant must exclude markerColoring's own commentary " +
                       "too — not just ThreadsDossierFormatter's per-recording marker section")
    }

    /// Same fixture, proving the senses-only variant (Creative/Gratitude)
    /// shares the same marker-free evaluate rather than a third, unguarded
    /// computation of its own.
    func testMarkerColoring_neverReachesSensesOnlyVariant() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let result = markerColoringFixtureDossiers()
        XCTAssertNotNil(result.dossierSensesOnly)
        XCTAssertFalse(result.dossierSensesOnly!.contains("Absolutist words cluster around"))
    }

    /// The senses-only variant carries `**Noticed:**` and nothing else — no
    /// heading, no marker section, no thread section — so Creative/Gratitude
    /// still see the walk's sensory content instead of losing the dossier
    /// outright.
    func testSensesOnlyVariant_carriesOnlyTheNoticedBlock() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let result = markerColoringFixtureDossiers()
        XCTAssertNotNil(result.dossierSensesOnly)
        XCTAssertTrue(result.dossierSensesOnly!.hasPrefix("**Noticed:**"))
        XCTAssertFalse(result.dossierSensesOnly!.contains("Thought threads"))
        XCTAssertFalse(result.dossierSensesOnly!.contains("Threads across recent walks"))
        XCTAssertFalse(result.dossierSensesOnly!.contains("Quiet this walk"))
    }

    // MARK: - `Noticed:` must reach the marker-free variant even with no thread section

    /// A walk whose speech carries no repeated noun produces no thread at
    /// all, so `ThreadsDossierFormatter.dossier(includeMarkerLines: false)`
    /// returns nil (`section == heading`) while the full dossier still
    /// renders its marker lines. The moon line fires regardless — it is a
    /// sense, not a thread claim — so `Noticed:` has real content to place.
    private func threadlessMoonFixtureDossiers() -> (
        dossier: String?, unchangedBlock: String?, dossierWithoutMarkers: String?, dossierSensesOnly: String?
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierNoticedRoutingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let defaults = UserDefaults(suiteName: "DossierNoticedRoutingTests-\(UUID().uuidString)")!

        let anchor = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let lunation = LunationCalendar.mostRecentClosed(asOf: anchor)
        let walkStart = lunation.start.addingTimeInterval(5 * 86400)
        let walkA = UUID(), recA = UUID()
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [recA: (walkA, walkStart)]
        // No noun survives to `minimumMentions`, so ThreadStore builds nothing.
        let recording = RecordingContext(
            text: String(repeating: "it was quiet and it stayed that way and nothing shifted at all ", count: 4),
            timestamp: walkStart.addingTimeInterval(300),
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: recA, endTimestamp: walkStart.addingTimeInterval(420)
        )
        let bundle = DossierSensesFetchBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            totalAscent: 0, elevationSeries: [], photos: [],
            walkSnapshots: [DossierSenses.WalkSnapshotRow(
                walkUUID: walkA, startDate: walkStart, intention: nil, weatherCondition: nil
            )],
            recordingTimestamps: [recA: walkStart.addingTimeInterval(300)],
            closedLunation: lunation, moonName: LunationCalendar.moonName(for: lunation)
        )

        return ThreadsDossierBuilder.buildResult(
            walkUUID: walkA, recordings: [recording], walkIndex: walkIndex,
            store: store, senses: bundle, resolveRouteFix: { _ in nil }, defaults: defaults
        )
    }

    /// Journaling reads `dossierWithoutMarkers`; Creative and Gratitude read
    /// `dossierSensesOnly`. When the marker-free render had no thread section
    /// to return, appending `Noticed:` only to an already-non-nil variant
    /// dropped it for Journaling alone — leaving the thread-analysis voice
    /// with LESS sensory context than the thread-suppressed ones.
    func testNoticed_reachesMarkerFreeVariant_evenWhenThereIsNoThreadSection() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true

        let result = threadlessMoonFixtureDossiers()
        XCTAssertNotNil(result.dossier)
        XCTAssertFalse(result.dossier!.contains("Threads across recent walks"),
                       "the fixture must produce no thread section, or it proves nothing")
        XCTAssertNotNil(result.dossierSensesOnly)
        XCTAssertTrue(result.dossierSensesOnly!.contains("has set"),
                      "the fixture must actually fire a sense")
        XCTAssertEqual(result.dossierWithoutMarkers, result.dossierSensesOnly,
                       "with no thread section there is nothing to hang Noticed: under, so the " +
                       "marker-free variant is the block itself — never nil")
    }
}
