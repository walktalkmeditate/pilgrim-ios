import Foundation

/// Single insertion point for PromptListView. Callable off the main actor:
/// the CoreStore walk index is fetched by the caller on the main actor and
/// passed in; everything else is file I/O and pure computation. Results are
/// memoized against the store's changeCount so reopening the prompt screen
/// doesn't re-read the whole context directory.
enum ThreadsDossierBuilder {

    private static var memo: (changeCount: Int, walkUUID: UUID, backfillComplete: Bool, dossier: String?)?
    private static let memoLock = NSLock()

    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared
    ) -> String? {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return nil }
        // One consistent read each, captured before any store mutation: a
        // mid-build mutation leaves the memoized changeCount stale, so the
        // next call rebuilds instead of absorbing the mutation unseen.
        let backfillComplete = ThreadsBackfill.isComplete
        let preBuildChangeCount = store.changeCount
        memoLock.lock()
        let cached = memo
        memoLock.unlock()
        if let cached, cached.changeCount == preBuildChangeCount,
           cached.walkUUID == walkUUID, cached.backfillComplete == backfillComplete {
            return cached.dossier
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
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordings: current,
            allContexts: allContexts,
            threads: threads,
            currentWalkUUID: walkUUID,
            backfillComplete: backfillComplete
        )
        memoLock.lock()
        memo = (preBuildChangeCount, walkUUID, backfillComplete, dossier)
        memoLock.unlock()
        return dossier
    }
}
