import Foundation
import CoreStore

/// Main-actor-fetched inputs for the senses block, gathered before the
/// detached build. Route fixes are NOT here — the builder resolves them
/// lazily, per needed recording, through `resolveRouteFix`.
struct DossierSensesFetchBundle {
    let walkStart: Date
    let walkEnd: Date
    let totalAscent: Double
    let elevationSeries: [DossierSenses.ElevationSample]
    let photos: [DossierSenses.PhotoPin]
    let walkSnapshots: [DossierSenses.WalkSnapshotRow]
    let recordingTimestamps: [UUID: Date]
    let closedLunation: Lunation
    let moonName: String
}

/// Single insertion point for PromptListView. Callable off the main actor:
/// the CoreStore walk index is fetched by the caller on the main actor and
/// passed in; everything else is file I/O and pure computation. Results are
/// memoized against the store's changeCount so reopening the prompt screen
/// doesn't re-read the whole context directory.
enum ThreadsDossierBuilder {

    static let moonLineDefaultsKey = "threadsMoonLineLastLunationIndex"

    /// `lunationIndex` and `intention` close two cache-miss gaps the other
    /// four fields can't detect: a lunation closing while the app stays
    /// resident (same walk, same store, same moon state — until the moon
    /// line itself fires and writes it) and an in-session intention edit
    /// (same walk, same store, nothing else moves). Both values already
    /// reach `build` via `senses`/`gatherSensesBundle` — this only widens
    /// what the memo compares. Bundled (like `SensesAssemblyState` below)
    /// to keep `cachedResult` under the function-parameter-count gate.
    struct MemoKey: Equatable {
        let changeCount: Int
        let walkUUID: UUID
        let backfillComplete: Bool
        let moonState: Int?
        let lunationIndex: Int?
        let intention: String?
    }

    private static var memo: (key: MemoKey, dossier: String?, unchangedBlock: String?)?
    private static let memoLock = NSLock()

    /// The one impure gather for the senses (spec architecture): cheap
    /// CoreStore snapshots on the main actor, value types out. Callers wrap
    /// this in the `threadsAfterWalks` check — off means no fetches at all.
    @MainActor
    static func gatherSensesBundle(walk: WalkInterface, now: Date = Date()) -> DossierSensesFetchBundle {
        let lunation = LunationCalendar.mostRecentClosed(asOf: now)
        let windowStart = walk.startDate.addingTimeInterval(-ThreadStore.recurrenceWindow)
        return DossierSensesFetchBundle(
            walkStart: walk.startDate,
            walkEnd: walk.endDate,
            totalAscent: walk.ascend,
            elevationSeries: walk.routeData.map {
                DossierSenses.ElevationSample(timestamp: $0.timestamp, altitude: $0.altitude)
            },
            photos: walk.walkPhotos.map { photo in
                // (-1, -1) is the schema's unset sentinel, not a place.
                DossierSenses.PhotoPin(
                    capturedAt: photo.capturedAt,
                    coordinate: photo.capturedLat == -1 && photo.capturedLng == -1
                        ? nil
                        : DossierSenses.Coordinate(latitude: photo.capturedLat, longitude: photo.capturedLng)
                )
            },
            walkSnapshots: DataManager.walkSensesSnapshot(
                from: min(windowStart, lunation.start),
                to: max(walk.endDate, lunation.end)
            ),
            recordingTimestamps: DataManager.voiceRecordingTimestampIndex(),
            closedLunation: lunation,
            moonName: LunationCalendar.moonName(for: lunation)
        )
    }

    /// Dossier-only entry point, unchanged for every existing caller —
    /// `buildResult` always computes `Unchanged:` too; this just discards it.
    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared,
        senses: DossierSensesFetchBundle? = nil,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix? = DataManager.routeFixNear,
        defaults: UserDefaults = .standard
    ) -> String? {
        buildResult(
            walkUUID: walkUUID, recordings: recordings, walkIndex: walkIndex, store: store,
            senses: senses, resolveRouteFix: resolveRouteFix, defaults: defaults
        ).dossier
    }

    /// Same computation as `build`, additionally surfacing the `Unchanged:`
    /// block computed alongside the dossier — the caller that needs both
    /// reads it here rather than triggering a second, per-voice build.
    static func buildResult(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared,
        senses: DossierSensesFetchBundle? = nil,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix? = DataManager.routeFixNear,
        defaults: UserDefaults = .standard
    ) -> (dossier: String?, unchangedBlock: String?) {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return (nil, nil) }
        // One consistent read each, captured before any store mutation: a
        // mid-build mutation leaves the memoized tokens stale, so the next
        // call rebuilds instead of absorbing the mutation unseen.
        let backfillComplete = ThreadsBackfill.isComplete
        let preBuildChangeCount = store.changeCount
        let moonState = defaults.object(forKey: moonLineDefaultsKey) as? Int
        let preBuildKey = memoKey(walkUUID: walkUUID, changeCount: preBuildChangeCount,
                                  backfillComplete: backfillComplete, moonState: moonState, senses: senses)
        if let cached = cachedResult(key: preBuildKey) {
            return cached
        }

        // Single directory decode per build: orphans come from the same load
        // that feeds the dossier, and fresh analyses are merged in by hand
        // instead of re-reading the directory afterwards. An empty walk index
        // alongside non-empty contexts is a failed/empty CoreStore read, not
        // proof of orphanhood — pruning then would delete every context.
        let all = store.loadAll()
        let orphans = walkIndex.isEmpty && !all.isEmpty
            ? Set<UUID>()
            : Set(TranscriptContextStore.orphans(in: all, keeping: Set(walkIndex.keys)))
        if !orphans.isEmpty {
            store.delete(recordingUUIDs: Array(orphans))
        }
        // The delete call above is one write regardless of orphan count
        // (`TranscriptContextStore.delete` bumps `changeCount` once per
        // call, not per UUID) — counted here so the memo baseline below can
        // add exactly this build's own confirmed writes instead of
        // re-sampling `store.changeCount` after the fact.
        let ownDeleteWrite = orphans.isEmpty ? 0 : 1
        let live = all.filter { !orphans.contains($0.recordingUUID) }

        let (current, freshlySaved) = resolveCurrentContexts(recordings: recordings, store: store)
        guard !current.isEmpty else { return (nil, nil) }

        var contextsByUUID = Dictionary(uniqueKeysWithValues: live.map { ($0.recordingUUID, $0) })
        for (uuid, context) in freshlySaved {
            contextsByUUID[uuid] = context
        }
        let allContexts = contextsByUUID.values
            .sorted { $0.recordingUUID.uuidString < $1.recordingUUID.uuidString }

        let threads = ThreadStore.build(contexts: allContexts, walks: walkIndex)

        var dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: current,
            allContexts: allContexts,
            threads: threads,
            currentWalkUUID: walkUUID,
            backfillComplete: backfillComplete,
            walkIndex: walkIndex.mapValues(\.walkUUID)
        )

        let sensesResult = appendSensesBlock(
            to: &dossier, senses: senses,
            state: SensesAssemblyState(
                walkUUID: walkUUID, recordings: recordings, contextsByUUID: contextsByUUID,
                threads: threads, walkIndex: walkIndex, backfillComplete: backfillComplete, moonState: moonState
            ),
            resolveRouteFix: resolveRouteFix, defaults: defaults
        )

        memoLock.lock()
        // Baseline is `preBuildChangeCount` plus exactly this build's own
        // confirmed writes (the orphan delete, if any, plus one save per
        // `freshlySaved` entry — each of those is a write `resolveCurrentContexts`
        // vouched for via `store.hasContext`) — never a fresh read of
        // `store.changeCount`. `changeCount` is a bare monotonic counter
        // with no writer attribution: an external writer (ThreadsBackfill's
        // sweep, transcription-completion analysis) landing a save inside
        // this same call — after `loadAll()` above already ran, so this
        // build never saw it — would otherwise get folded into the memo as
        // if it were this build's own mutation, and the next call for this
        // walk would then cache-hit a dossier that never saw it. Computing
        // the baseline from only confirmed own-writes means any external
        // change, including one landing inside this build's own window,
        // still invalidates the memo on the next call. Reopening the same
        // walk with no writes at all in between still hits the memo.
        let ownWriteCount = ownDeleteWrite + freshlySaved.count
        let postBuildKey = memoKey(walkUUID: walkUUID, changeCount: preBuildChangeCount + ownWriteCount,
                                   backfillComplete: backfillComplete, moonState: sensesResult.moonState, senses: senses)
        memo = (postBuildKey, dossier, sensesResult.unchangedBlock)
        memoLock.unlock()
        return (dossier, sensesResult.unchangedBlock)
    }

    /// Outer optional is cache presence; the dossier field inside a hit can
    /// itself legitimately be nil — a memoized nil dossier is a valid,
    /// distinct cache hit from no cache at all.
    private static func cachedResult(key: MemoKey) -> (dossier: String?, unchangedBlock: String?)? {
        memoLock.lock()
        defer { memoLock.unlock() }
        guard let cached = memo, cached.key == key else { return nil }
        return (cached.dossier, cached.unchangedBlock)
    }

    /// `lunationIndex`/`intention` both derive from `senses` the same way at
    /// both call sites (pre-build lookup, post-build write) — factored here
    /// so `build` states each `MemoKey` in one line.
    private static func memoKey(
        walkUUID: UUID, changeCount: Int, backfillComplete: Bool, moonState: Int?,
        senses: DossierSensesFetchBundle?
    ) -> MemoKey {
        MemoKey(
            changeCount: changeCount, walkUUID: walkUUID, backfillComplete: backfillComplete,
            moonState: moonState, lunationIndex: senses?.closedLunation.index,
            intention: senses?.walkSnapshots.first { $0.walkUUID == walkUUID }?.intention
        )
    }

    /// Resolves each current recording's context — hash-matched cache hit,
    /// or a lazy-backfill analysis persisted under the real UUID so the
    /// store self-heals (also covers edited transcripts whose stored hash no
    /// longer matches). `freshlySaved` collects only what actually reached
    /// disk — a tombstone-blocked save reports success but writes nothing —
    /// so the memo's own-write count in `build` stays honest.
    private static func resolveCurrentContexts(
        recordings: [RecordingContext], store: TranscriptContextStore
    ) -> (current: [(context: TranscriptContext, wordsPerMinute: Double?)], freshlySaved: [UUID: TranscriptContext]) {
        var freshlySaved: [UUID: TranscriptContext] = [:]
        let current: [(context: TranscriptContext, wordsPerMinute: Double?)] = recordings.compactMap { recording in
            guard let uuid = recording.recordingUUID else { return nil }
            let hash = TranscriptContextStore.hash(of: recording.text)
            if let stored = store.context(for: uuid, matching: hash) {
                return (stored, recording.wordsPerMinute)
            }
            let result = TranscriptContextAnalyzer.analyzeAndStore(
                recordingUUID: uuid, transcript: recording.text, store: store
            )
            if result.saved && store.hasContext(for: uuid) {
                freshlySaved[uuid] = result.context
            }
            return (result.context, recording.wordsPerMinute)
        }
        return (current, freshlySaved)
    }

    /// Everything `makeSensesInput` needs beyond the senses bundle itself —
    /// bundled to keep both it and `appendSensesBlock` under the
    /// function-parameter-count lint gate.
    struct SensesAssemblyState {
        let walkUUID: UUID
        let recordings: [RecordingContext]
        let contextsByUUID: [UUID: TranscriptContext]
        let threads: [WalkThread]
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)]
        let backfillComplete: Bool
        let moonState: Int?
    }

    /// Appends the `Noticed:` block, renders `Unchanged:` from the SAME
    /// `input` (never a second `DossierSenses.Input`), and records the
    /// moon-line UserDefaults write. `moonState` carries forward unchanged
    /// unless the moon line fired; `unchangedBlock` is nil when no
    /// invariant fired or there is no dossier to attach it to.
    private static func appendSensesBlock(
        to dossier: inout String?,
        senses: DossierSensesFetchBundle?,
        state: SensesAssemblyState,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix?,
        defaults: UserDefaults
    ) -> (moonState: Int?, unchangedBlock: String?) {
        guard let senses, dossier != nil else { return (state.moonState, nil) }
        let input = makeSensesInput(senses: senses, state: state, resolveRouteFix: resolveRouteFix)
        let output = DossierSenses.lines(input: input)
        if !output.lines.isEmpty {
            dossier! += "\n\n**Noticed:**\n" + output.lines.joined(separator: "\n")
        }
        let unchangedBlock = renderUnchangedBlock(DossierSenses.invarianceLines(input: input))
        guard let reported = output.reportedLunationIndex else { return (state.moonState, unchangedBlock) }
        defaults.set(reported, forKey: moonLineDefaultsKey)
        return (reported, unchangedBlock)
    }

    /// Renders invariance lines into the block the assembler emits. Nil for
    /// an empty list, so `unchangedBlock` is absent rather than an empty
    /// heading — the same shape `ThreadsDossierFormatter.dossier` uses.
    static func renderUnchangedBlock(_ lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        return "**Unchanged:**\n" + lines.joined(separator: "\n")
    }

    /// Route fixes for exactly the recordings that can anchor a location
    /// claim: in-window mention recordings (any thread — the baseline needs
    /// them all) plus the current walk's themed recordings.
    private static func resolveFixes(
        threads: [WalkThread], currentRecordings: [DossierSenses.CurrentRecording],
        senses: DossierSensesFetchBundle, resolveRouteFix: (Date) -> DossierSenses.RouteFix?
    ) -> [UUID: DossierSenses.RouteFix] {
        let windowStart = senses.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        var needed = Set<UUID>()
        for thread in threads {
            for appearance in thread.appearances {
                guard let instant = senses.recordingTimestamps[appearance.recordingUUID],
                      instant >= windowStart, instant <= senses.walkEnd else { continue }
                needed.insert(appearance.recordingUUID)
            }
        }
        for recording in currentRecordings where !recording.themes.isEmpty {
            needed.insert(recording.uuid)
        }
        var fixes: [UUID: DossierSenses.RouteFix] = [:]
        for uuid in needed.sorted(by: { $0.uuidString < $1.uuidString }) {
            let timestamp = senses.recordingTimestamps[uuid]
                ?? currentRecordings.first { $0.uuid == uuid }?.start
            if let timestamp, let fix = resolveRouteFix(timestamp) {
                fixes[uuid] = fix
            }
        }
        return fixes
    }

    /// Bridges builder-held data into the pure module's Input.
    static func makeSensesInput(
        senses: DossierSensesFetchBundle,
        state: SensesAssemblyState,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix?
    ) -> DossierSenses.Input {
        let currentRecordings: [DossierSenses.CurrentRecording] = state.recordings.compactMap { recording in
            guard let uuid = recording.recordingUUID,
                  let context = state.contextsByUUID[uuid] else { return nil }
            return DossierSenses.CurrentRecording(
                uuid: uuid,
                start: recording.timestamp,
                end: recording.endTimestamp ?? recording.timestamp,
                text: recording.text,
                wordCount: context.wordCount,
                themes: context.themes
            )
        }

        let fixes = resolveFixes(
            threads: state.threads, currentRecordings: currentRecordings,
            senses: senses, resolveRouteFix: resolveRouteFix
        )

        var wordedWalkDates: [UUID: Date] = [:]
        for (uuid, context) in state.contextsByUUID where context.wordCount > 0 {
            if let walk = state.walkIndex[uuid] {
                wordedWalkDates[walk.walkUUID] = walk.date
            }
        }
        let moon = DossierSenses.MoonInput(
            lunationIndex: senses.closedLunation.index,
            moonName: senses.moonName,
            start: senses.closedLunation.start,
            end: senses.closedLunation.end,
            lastReportedIndex: state.moonState,
            currentWalkHasWords: currentRecordings.contains { $0.wordCount > 0 },
            allWalkDates: senses.walkSnapshots.map(\.startDate),
            wordedWalkDates: Array(wordedWalkDates.values)
        )

        return DossierSenses.Input(
            currentWalkUUID: state.walkUUID,
            walkStart: senses.walkStart,
            walkEnd: senses.walkEnd,
            totalAscent: senses.totalAscent,
            elevationSeries: senses.elevationSeries,
            photos: senses.photos,
            currentRecordings: currentRecordings,
            historicalContexts: state.contextsByUUID.values
                .sorted { $0.recordingUUID.uuidString < $1.recordingUUID.uuidString },
            threads: state.threads,
            backfillComplete: state.backfillComplete,
            walkSnapshots: senses.walkSnapshots,
            recordingTimestamps: senses.recordingTimestamps,
            fixes: fixes,
            moon: moon
        )
    }
}
