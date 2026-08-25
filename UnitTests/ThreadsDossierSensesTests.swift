import XCTest
@testable import Pilgrim

/// Senses bundle integration — the builder gathers, resolves, appends the
/// `Noticed:` block, and owns the moon-line state machine. Split from
/// `ThreadsDossierTests` to keep both files under the file_length /
/// type_body_length lint gates (plan house rule: split rather than accept a
/// new warning).
extension ThreadsDossierTests {

    private func sensesBundle(
        walkStart: Date, walkEnd: Date,
        walkSnapshots: [DossierSenses.WalkSnapshotRow] = [],
        recordingTimestamps: [UUID: Date] = [:],
        lunationAnchor: Date
    ) -> DossierSensesFetchBundle {
        let lunation = LunationCalendar.mostRecentClosed(asOf: lunationAnchor)
        return DossierSensesFetchBundle(
            walkStart: walkStart, walkEnd: walkEnd, totalAscent: 0,
            elevationSeries: [], photos: [], walkSnapshots: walkSnapshots,
            historyTranscripts: [], recordingTimestamps: recordingTimestamps,
            closedLunation: lunation, moonName: LunationCalendar.moonName(for: lunation)
        )
    }

    private func wordedRecording(uuid: UUID, start: Date) -> RecordingContext {
        RecordingContext(
            text: String(repeating: "the move keeps returning to me today ", count: 6),
            timestamp: start, startCoordinate: nil, endCoordinate: nil,
            wordsPerMinute: nil, recordingUUID: uuid, endTimestamp: start.addingTimeInterval(120)
        )
    }

    /// One worded-recording build, route fixes stubbed out — every senses
    /// fixture below only needs the moon line, which carries no location.
    private func build(
        walk: (uuid: UUID, recordingUUID: UUID, start: Date),
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        bundle: DossierSensesFetchBundle, store: TranscriptContextStore
    ) -> String? {
        ThreadsDossierBuilder.build(
            walkUUID: walk.uuid, recordings: [wordedRecording(uuid: walk.recordingUUID, start: walk.start)],
            walkIndex: walkIndex, store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
    }

    func testBuilder_sensesBundle_appendsNoticedBlock_andMoonReportsOnce() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let defaults = UserDefaults.standard
        let savedMoon = defaults.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        defer {
            if let savedMoon { defaults.set(savedMoon, forKey: ThreadsDossierBuilder.moonLineDefaultsKey) }
            else { defaults.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey) }
        }
        defaults.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        // A walk dated just after a lunation close, with a worded walk inside
        // the closed lunation, so the moon line has something true to say.
        let now = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let lunation = LunationCalendar.mostRecentClosed(asOf: now)
        let walkStart = lunation.end.addingTimeInterval(3 * 86400)
        let walkA = UUID(), recA = UUID()
        let lunationWalk = UUID(), lunationRec = UUID()
        let lunationDate = lunation.start.addingTimeInterval(5 * 86400)
        _ = TranscriptContextAnalyzer.analyzeAndStore(
            recordingUUID: lunationRec,
            transcript: String(repeating: "the move keeps returning to me today ", count: 6),
            store: store
        )
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [
            recA: (walkA, walkStart), lunationRec: (lunationWalk, lunationDate)
        ]
        let bundle = sensesBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            walkSnapshots: [
                DossierSenses.WalkSnapshotRow(walkUUID: lunationWalk, startDate: lunationDate,
                                              intention: nil, weatherCondition: nil),
                DossierSenses.WalkSnapshotRow(walkUUID: walkA, startDate: walkStart,
                                              intention: nil, weatherCondition: nil)
            ],
            recordingTimestamps: [recA: walkStart.addingTimeInterval(300),
                                  lunationRec: lunationDate.addingTimeInterval(300)],
            lunationAnchor: now
        )

        let first = build(walk: (walkA, recA, walkStart.addingTimeInterval(300)),
                          walkIndex: walkIndex, bundle: bundle, store: store)
        XCTAssertNotNil(first)
        XCTAssertTrue(first!.contains("**Noticed:**"))
        XCTAssertTrue(first!.contains("has set"), "the closed lunation's line rides the first build after it")
        XCTAssertEqual(defaults.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey) as? Int,
                       bundle.closedLunation.index)

        // Memo: the same walk keeps its moon line on reopen.
        let again = build(walk: (walkA, recA, walkStart.addingTimeInterval(300)),
                          walkIndex: walkIndex, bundle: bundle, store: store)
        XCTAssertEqual(again, first)

        // A different walk in the same lunation: reported already — no line.
        let walkB = UUID(), recB = UUID()
        var indexB = walkIndex
        indexB[recB] = (walkB, walkStart.addingTimeInterval(86400))
        let second = build(walk: (walkB, recB, walkStart.addingTimeInterval(86400)),
                           walkIndex: indexB, bundle: bundle, store: store)
        XCTAssertNotNil(second)
        XCTAssertFalse(second!.contains("has set"), "once per lunation — the second walk stays quiet")
    }

    func testBuilder_nilSensesBundle_dossierUnchangedFromToday() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let uuid = UUID()
        let dossier = ThreadsDossierBuilder.build(
            walkUUID: UUID(),
            recordings: [wordedRecording(uuid: uuid, start: DateFactory.makeDate(2024, 6, 15, 9, 0, 0))],
            walkIndex: [:], store: store
        )
        XCTAssertNotNil(dossier)
        XCTAssertFalse(dossier!.contains("**Noticed:**"),
                       "no bundle, no block — existing callers and tests see today's dossier")
    }

    func testBuilder_recordingWithoutUUID_noDossierAtAll_firingSenseNeverLeaksThrough() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        // A recording with no `recordingUUID` can never enter `current` — the
        // formatter's dossier is nil by the same guard the builder already
        // short-circuits on. A senses bundle built to fire (a worded walk
        // inside a closed lunation) must still leak nothing: the `if let
        // senses, dossier != nil` gate holds even when a sense has something
        // to say — the same structural guarantee the marker line's
        // handling-note co-presence claim rests on, proven from the other
        // direction.
        let now = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let lunation = LunationCalendar.mostRecentClosed(asOf: now)
        let walkStart = lunation.end.addingTimeInterval(3 * 86400)
        let walkA = UUID()
        let lunationWalk = UUID(), lunationRec = UUID()
        let lunationDate = lunation.start.addingTimeInterval(5 * 86400)
        _ = TranscriptContextAnalyzer.analyzeAndStore(
            recordingUUID: lunationRec,
            transcript: String(repeating: "the move keeps returning to me today ", count: 6),
            store: store
        )
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [lunationRec: (lunationWalk, lunationDate)]
        let bundle = sensesBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            walkSnapshots: [
                DossierSenses.WalkSnapshotRow(walkUUID: lunationWalk, startDate: lunationDate,
                                              intention: nil, weatherCondition: nil)
            ],
            recordingTimestamps: [lunationRec: lunationDate.addingTimeInterval(300)],
            lunationAnchor: now
        )
        let recordingWithoutUUID = RecordingContext(
            text: "words that never earn a dossier", timestamp: walkStart,
            startCoordinate: nil, endCoordinate: nil, wordsPerMinute: nil,
            recordingUUID: nil, endTimestamp: walkStart.addingTimeInterval(120)
        )

        let dossier = ThreadsDossierBuilder.build(
            walkUUID: walkA, recordings: [recordingWithoutUUID],
            walkIndex: walkIndex, store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
        XCTAssertNil(dossier, "no thread-bearing recording — no dossier, and a firing sense cannot conjure one")
    }

    /// The memo must count only the build's own writes, not whatever
    /// `store.changeCount` happens to read as afterward. `resolveRouteFix`
    /// is the one hook `build` calls mid-execution (inside
    /// `appendSensesBlock`, after the pre-build changeCount is sampled and
    /// before the memo is written) — using it to fire an external
    /// `store.save` reproduces a background writer (ThreadsBackfill's
    /// sweep, transcription-completion analysis) landing a context inside
    /// that exact window, something a real timer/queue can do but a
    /// same-thread test otherwise can't.
    func testBuilder_externalWriteDuringBuildWindow_notFoldedIntoMemo_nextCallMisses() {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = true
        let defaults = UserDefaults.standard
        let savedMoon = defaults.object(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
        defer {
            if let savedMoon { defaults.set(savedMoon, forKey: ThreadsDossierBuilder.moonLineDefaultsKey) }
            else { defaults.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey) }
        }
        defaults.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DossierSensesBuilderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)

        let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let walkA = UUID(), recA = UUID()
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)] = [recA: (walkA, walkStart)]
        let bundle = sensesBundle(
            walkStart: walkStart, walkEnd: walkStart.addingTimeInterval(3600),
            recordingTimestamps: [recA: walkStart.addingTimeInterval(300)],
            lunationAnchor: walkStart
        )
        // Never-before-stored, so build 1's lazy backfill fires and this
        // build's own-write count is 1, not 0.
        let recording = wordedRecording(uuid: recA, start: walkStart.addingTimeInterval(300))

        // A UUID no walkIndex here ever claims — an orphan the moment it's
        // seen by a fresh `store.loadAll()`.
        let externalUUID = UUID()
        let midBuildExternalWrite: (Date) -> DossierSenses.RouteFix? = { _ in
            let context = TranscriptContextAnalyzer.analyze(
                recordingUUID: externalUUID, transcript: "a note that belongs to no walk this build knows about"
            )
            store.save(context)
            return nil
        }

        _ = ThreadsDossierBuilder.build(
            walkUUID: walkA, recordings: [recording], walkIndex: walkIndex,
            store: store, senses: bundle, resolveRouteFix: midBuildExternalWrite
        )
        XCTAssertTrue(store.hasContext(for: externalUUID), "the external write must have actually landed mid-build")

        // Same walk, same recordings, same index, no further external
        // writes — the T9 reopen shape. Build 1's own `loadAll()` ran
        // before the external write landed, so it never pruned
        // `externalUUID` as the orphan it is. A memo that folded that
        // external bump into its own baseline would cache-hit here and
        // leave it stranded on disk forever (self-healing only on some
        // unrelated future mutation). The correct memo misses, rebuilds,
        // and prunes it.
        _ = ThreadsDossierBuilder.build(
            walkUUID: walkA, recordings: [recording], walkIndex: walkIndex,
            store: store, senses: bundle, resolveRouteFix: { _ in nil }
        )
        XCTAssertFalse(store.hasContext(for: externalUUID),
                       "build 2 must re-read the store and prune the external write as an orphan")
    }

    func testAssembler_noticedBlockRidesInsideDossier_handlingNoteCoPresent() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let dossier = "**Thought threads (on-device analysis):**\ntest\n\n**Noticed:**\n'music' has surfaced on 2 walks — twice near the same stretch of ground."
        let context = ActivityContext.make(startDate: start, threadsDossier: dossier)
        let prompt = PromptAssembler.assemble(context: context, voice: PromptStyle.allCases[0].voice)
        XCTAssertTrue(prompt.contains("**Noticed:**"))
        XCTAssertTrue(prompt.contains("not assessments"),
                      "the dossier's presence triggers the marker handling note — the binding co-presence gate")
    }
}
