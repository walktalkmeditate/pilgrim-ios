import Foundation

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

    private static var memo: (
        changeCount: Int, walkUUID: UUID, backfillComplete: Bool,
        moonState: Int?, dossier: String?
    )?
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
        if let cached = cachedDossier(walkUUID: walkUUID, changeCount: preBuildChangeCount,
                                      backfillComplete: backfillComplete, moonState: moonState) {
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
        let live = all.filter { !orphans.contains($0.recordingUUID) }

        var freshlySaved: [UUID: TranscriptContext] = [:]
        let current: [(context: TranscriptContext, wordsPerMinute: Double?)] = recordings.compactMap { recording in
            guard let uuid = recording.recordingUUID else { return nil }
            let hash = TranscriptContextStore.hash(of: recording.text)
            if let stored = store.context(for: uuid, matching: hash) {
                return (stored, recording.wordsPerMinute)
            }
            // Lazy-backfill fallback, persisted under the real UUID so the
            // store self-heals instead of re-analyzing on every open. Also
            // covers edited transcripts whose stored hash no longer matches.
            let result = TranscriptContextAnalyzer.analyzeAndStore(
                recordingUUID: uuid, transcript: recording.text, store: store
            )
            // Merge only what actually reached disk — a tombstone-blocked
            // save reports true but writes nothing.
            if result.saved && store.hasContext(for: uuid) {
                freshlySaved[uuid] = result.context
            }
            return (result.context, recording.wordsPerMinute)
        }
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
        // Post-write changeCount and moon state: this build's own lazy
        // backfill can itself bump the store's changeCount, so memoizing the
        // pre-build snapshot would make the very next identical call miss
        // its own cache. Reading again here captures this build's mutations
        // (if any) as the new baseline — reopening the same walk hits the
        // memo and keeps its moon line; any other walk, or a change from
        // elsewhere, still invalidates it.
        memo = (store.changeCount, walkUUID, backfillComplete, postBuildMoonState, dossier)
        memoLock.unlock()
        return dossier
    }

    /// `String??`: outer optional is cache presence, inner is the dossier
    /// itself — a memoized nil dossier is a valid, distinct cache hit from
    /// no cache at all.
    private static func cachedDossier(
        walkUUID: UUID, changeCount: Int, backfillComplete: Bool, moonState: Int?
    ) -> String?? {
        memoLock.lock()
        defer { memoLock.unlock() }
        guard let cached = memo, cached.changeCount == changeCount,
              cached.walkUUID == walkUUID, cached.backfillComplete == backfillComplete,
              cached.moonState == moonState else { return nil }
        return cached.dossier
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
