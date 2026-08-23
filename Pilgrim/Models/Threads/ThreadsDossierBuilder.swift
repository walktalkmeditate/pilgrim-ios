import Foundation

/// Single insertion point for PromptListView. Callable off the main actor:
/// the CoreStore walk index is fetched by the caller on the main actor and
/// passed in; everything else is file I/O and pure computation. Results are
/// memoized against the store's changeCount so reopening the prompt screen
/// doesn't re-read the whole context directory.
enum ThreadsDossierBuilder {

    private static var memo: (changeCount: Int, walkUUID: UUID, dossier: String?)?

    static func build(
        walkUUID: UUID,
        recordings: [RecordingContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        store: TranscriptContextStore = .shared
    ) -> String? {
        guard UserPreferences.threadsAfterWalks.value, !recordings.isEmpty else { return nil }
        if let memo, memo.changeCount == store.changeCount, memo.walkUUID == walkUUID {
            return memo.dossier
        }

        store.pruneOrphans(keeping: Set(walkIndex.keys))

        let current = recordings.compactMap { recording -> TranscriptContext? in
            guard let uuid = recording.recordingUUID else { return nil }
            let hash = TranscriptContextStore.hash(of: recording.text)
            if let stored = store.context(for: uuid, matching: hash) { return stored }
            // Lazy-backfill fallback, persisted under the real UUID so the
            // store self-heals instead of re-analyzing on every open. Also
            // covers edited transcripts whose stored hash no longer matches.
            return TranscriptContextAnalyzer.analyzeAndStore(
                recordingUUID: uuid, transcript: recording.text, store: store
            )
        }
        guard !current.isEmpty else { return nil }

        let all = store.loadAll()
        let threads = ThreadStore.build(contexts: all, walks: walkIndex)
        let dossier = ThreadsDossierFormatter.dossier(
            currentRecordingContexts: current,
            allContexts: all,
            threads: threads,
            currentWalkUUID: walkUUID,
            backfillComplete: ThreadsBackfill.isComplete
        )
        memo = (store.changeCount, walkUUID, dossier)
        return dossier
    }
}
