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
    let historyTranscripts: [(recordingUUID: UUID, transcript: String)]
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
    /// to keep `cachedDossier` under the function-parameter-count gate.
    struct MemoKey: Equatable {
        let changeCount: Int
        let walkUUID: UUID
        let backfillComplete: Bool
        let moonState: Int?
        let lunationIndex: Int?
        let intention: String?
    }

    private static var memo: (key: MemoKey, dossier: String?)?
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
            // Relabeled: `transcribedRecordingsSnapshot` returns `uuid:`,
            // matching its other DataManager snapshot siblings; the senses
            // bundle's tuple shape is `recordingUUID:`, matching
            // `DossierSenses.Input` — the labels are structurally
            // interchangeable but Swift does not convert them implicitly.
            historyTranscripts: DataManager.transcribedRecordingsSnapshot(in: windowStart...walk.endDate)
                .map { (recordingUUID: $0.uuid, transcript: $0.transcript) },
            recordingTimestamps: DataManager.voiceRecordingTimestampIndex(),
            closedLunation: lunation,
            moonName: LunationCalendar.moonName(for: lunation)
        )
    }

    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared,
        senses: DossierSensesFetchBundle? = nil,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix? = DataManager.routeFixNear,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return nil }
        // One consistent read each, captured before any store mutation: a
        // mid-build mutation leaves the memoized tokens stale, so the next
        // call rebuilds instead of absorbing the mutation unseen.
        let backfillComplete = ThreadsBackfill.isComplete
        let preBuildChangeCount = store.changeCount
        let moonState = defaults.object(forKey: moonLineDefaultsKey) as? Int
        let preBuildKey = memoKey(walkUUID: walkUUID, changeCount: preBuildChangeCount,
                                  backfillComplete: backfillComplete, moonState: moonState, senses: senses)
        if let cached = cachedDossier(key: preBuildKey) {
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
        guard !current.isEmpty else { return nil }

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
            backfillComplete: backfillComplete
        )

        let postBuildMoonState = appendSensesBlock(
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
                                   backfillComplete: backfillComplete, moonState: postBuildMoonState, senses: senses)
        memo = (postBuildKey, dossier)
        memoLock.unlock()
        return dossier
    }

    /// `String??`: outer optional is cache presence, inner is the dossier
    /// itself — a memoized nil dossier is a valid, distinct cache hit from
    /// no cache at all.
    private static func cachedDossier(key: MemoKey) -> String?? {
        memoLock.lock()
        defer { memoLock.unlock() }
        guard let cached = memo, cached.key == key else { return nil }
        return cached.dossier
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

    /// Appends the `Noticed:` block when a sense has something to say and
    /// records the moon-line UserDefaults write. Returns the moon state the
    /// memo should carry forward — unchanged when nothing fired, the newly
    /// reported lunation when the moon line did.
    private static func appendSensesBlock(
        to dossier: inout String?,
        senses: DossierSensesFetchBundle?,
        state: SensesAssemblyState,
        resolveRouteFix: (Date) -> DossierSenses.RouteFix?,
        defaults: UserDefaults
    ) -> Int? {
        guard let senses, dossier != nil else { return state.moonState }
        let input = makeSensesInput(senses: senses, state: state, resolveRouteFix: resolveRouteFix)
        let output = DossierSenses.lines(input: input)
        if !output.lines.isEmpty {
            dossier! += "\n\n**Noticed:**\n" + output.lines.joined(separator: "\n")
        }
        guard let reported = output.reportedLunationIndex else { return state.moonState }
        defaults.set(reported, forKey: moonLineDefaultsKey)
        return reported
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
            threads: state.threads,
            backfillComplete: state.backfillComplete,
            walkSnapshots: senses.walkSnapshots,
            historyTranscripts: senses.historyTranscripts,
            recordingTimestamps: senses.recordingTimestamps,
            walkIndex: state.walkIndex,
            fixes: fixes,
            moon: moon
        )
    }
}

#if DEBUG
/// Ship-gate harness (spec Ship gate item 1): iterates every walk with
/// transcribed recordings, evaluates every sense uncapped, and prints
/// per-sense firing rates plus each emitted line, so a human can judge
/// degeneration (fires on nearly every walk) and dead senses (nearly never)
/// against a REAL device history. Launch the dev build on the team device
/// with `--senses-field-report` and read the console. The report only
/// EVALUATES senses (moon state passed as nil, no defaults write anywhere
/// on this path) — it never consumes the real once-per-lunation budget.
enum DossierSensesFieldReport {

    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--senses-field-report"),
              NSClassFromString("XCTestCase") == nil else { return }
        print(generate())
    }

    @MainActor
    static func generate(now: Date = Date()) -> String {
        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>().orderBy(.ascending(\._startDate))
        ) else { return "senses field report: walk fetch failed" }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let all = TranscriptContextStore.shared.loadAll()
        let context = FieldReportContext(
            contextsByUUID: Dictionary(uniqueKeysWithValues: all.map { ($0.recordingUUID, $0) }),
            threadsAll: ThreadStore.build(contexts: all, walks: walkIndex),
            walkIndex: walkIndex
        )
        var firing: [DossierSenses.Sense: Int] = [:]
        var eligible = 0
        var buildDurations: [TimeInterval] = []
        var report = "\n===== DOSSIER SENSES FIELD REPORT =====\n"
        if walks.isEmpty {
            report += "\n(no walk history on this device — nothing to report)\n"
            report += "=======================================\n"
            return report
        }
        for walk in walks {
            guard let walkUUID = walk._uuid.value else { continue }
            let recordings = transcribedRecordings(for: walk)
            guard !recordings.isEmpty else { continue }
            eligible += 1
            let result = evaluateWalk(walk, walkUUID: walkUUID, recordings: recordings, now: now, context: context)
            report += result.text
            for sense in result.firingSenses { firing[sense, default: 0] += 1 }
            buildDurations.append(result.buildSeconds)
        }
        if eligible == 0 {
            report += "\n(no walk carries a transcribed recording — nothing to report)\n"
            report += "=======================================\n"
            return report
        }
        report += "\nFiring rates over \(eligible) walks with words:\n"
        for sense in DossierSenses.Sense.allCases {
            report += "  \(sense): \(firing[sense] ?? 0)/\(eligible)\n"
        }
        let sortedDurations = buildDurations.sorted()
        let midpoint = sortedDurations.count / 2
        let medianSeconds = sortedDurations.count.isMultiple(of: 2)
            ? (sortedDurations[midpoint - 1] + sortedDurations[midpoint]) / 2
            : sortedDurations[midpoint]
        let maxSeconds = sortedDurations.last ?? 0
        report += String(format: "\nBuild time — median: %.3fs, max: %.3fs\n", medianSeconds, maxSeconds)
        report += "=======================================\n"
        return report
    }

    /// Bundled so `evaluateWalk` stays under the function-parameter-count
    /// lint gate — same rationale as `ThreadsDossierBuilder.SensesAssemblyState`.
    private struct FieldReportContext {
        let contextsByUUID: [UUID: TranscriptContext]
        let threadsAll: [WalkThread]
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)]
    }

    private struct WalkSensesReport {
        let text: String
        let firingSenses: [DossierSenses.Sense]
        let buildSeconds: TimeInterval
    }

    private static func transcribedRecordings(for walk: Walk) -> [RecordingContext] {
        walk._voiceRecordings.value.compactMap { recording in
            guard let uuid = recording._uuid.value,
                  let text = recording._transcription.value, !text.isEmpty else { return nil }
            return RecordingContext(
                text: text, timestamp: recording._startDate.value,
                startCoordinate: nil, endCoordinate: nil,
                wordsPerMinute: recording._wordsPerMinute.value,
                recordingUUID: uuid, endTimestamp: recording._endDate.value
            )
        }
    }

    /// Evaluates every sense for one walk and prints its per-walk build
    /// wall-clock (ship-gate item: judge per-walk cost, not just firing
    /// rates). Wall-clock, not ContinuousClock — this DEBUG harness prints a
    /// human-facing diagnostic, not a pure-module measurement; the pure
    /// senses functions themselves stay Date()-free.
    @MainActor
    private static func evaluateWalk(
        _ walk: Walk, walkUUID: UUID, recordings: [RecordingContext], now: Date, context: FieldReportContext
    ) -> WalkSensesReport {
        let buildStart = Date()
        let bundle = ThreadsDossierBuilder.gatherSensesBundle(walk: walk, now: now)
        let input = ThreadsDossierBuilder.makeSensesInput(
            senses: bundle,
            state: ThreadsDossierBuilder.SensesAssemblyState(
                walkUUID: walkUUID, recordings: recordings, contextsByUUID: context.contextsByUUID,
                threads: context.threadsAll, walkIndex: context.walkIndex,
                backfillComplete: ThreadsBackfill.isComplete, moonState: nil
            ),
            resolveRouteFix: DataManager.routeFixNear
        )
        var text = "\nWalk \(walk._startDate.value):\n"
        var firingSenses: [DossierSenses.Sense] = []
        for sense in DossierSenses.Sense.allCases {
            guard let line = DossierSenses.evaluate(sense, input: input, suppressed: []) else { continue }
            firingSenses.append(sense)
            text += "  [\(sense)] \(line.text)\n"
        }
        let buildSeconds = Date().timeIntervalSince(buildStart)
        text += String(format: "  build: %.3fs\n", buildSeconds)
        return WalkSensesReport(text: text, firingSenses: firingSenses, buildSeconds: buildSeconds)
    }
}
#endif
