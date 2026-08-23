import Foundation

/// One-time pass over already-transcribed recordings when the feature first
/// activates — origin claims ("first time", "where it began") are only true
/// once history is fully analyzed (spec: ThreadStore).
enum ThreadsBackfill {

    static let completedKey = "threadsBackfillCompleted"
    private static var isRunning = false
    private static var generation = 0

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    /// Called from PilgrimPackageImporter's success path: imports bypass the
    /// transcription choke point, so the flag resets and the next launch
    /// sweeps the imported recordings (origin labels re-suppress meanwhile).
    /// Bumping the generation keeps a backfill already in flight from
    /// clobbering the reset when it completes — its snapshot predates the
    /// import. Importer completions land on the main queue (CoreStore's
    /// default), the only place the counter is touched.
    static func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation += 1
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    private static let batchSize = 25

    /// Main-actor only: the CoreStore snapshot must be taken before
    /// detaching — `dataStack.fetchAll` asserts main-thread. Single-flight,
    /// and battery-gated like MainCoordinator.triggerAutoTranscription.
    /// Fills MISSING contexts only: a hash-mismatched (edited) recording is
    /// owned by the edit trigger, and overwriting it here would race a
    /// newer analysis with this launch's stale snapshot.
    ///
    /// The completed flag is set only when every snapshot item is accounted
    /// for — saved by this sweep, or already on disk after the attempt.
    /// A failed save (or the battery gate closing mid-sweep) leaves the flag
    /// false so the next launch retries just the missing ones.
    ///
    /// Off means no analysis at all, not just no surfacing — re-enabling the
    /// toggle resweeps via the `ThreadsBackfill.reset()` call in VoiceCard.
    @MainActor
    static func runIfNeeded(store: TranscriptContextStore = .shared) {
        guard !isComplete, !isRunning, UserPreferences.threadsAfterWalks.value else { return }
        guard BatteryGate.allowsBackgroundWork() else { return }
        isRunning = true

        let startGeneration = generation
        let items = DataManager.transcribedRecordingsSnapshot()
        Task.detached(priority: .utility) {
            var allAccounted = true
            var gateClosed = false
            var batchStart = 0
            while batchStart < items.count {
                guard await MainActor.run(body: { BatteryGate.allowsBackgroundWork() }) else {
                    gateClosed = true
                    break
                }
                let batch = items[batchStart..<min(batchStart + batchSize, items.count)]
                for item in batch where !store.hasContext(for: item.uuid) {
                    let saved = TranscriptContextAnalyzer.analyzeAndStore(
                        recordingUUID: item.uuid,
                        transcript: item.transcript,
                        store: store
                    ).saved
                    if !saved && !store.hasContext(for: item.uuid) {
                        allAccounted = false
                    }
                }
                batchStart += batchSize
                await Task.yield()
            }
            await MainActor.run {
                if generation == startGeneration && allAccounted && !gateClosed {
                    UserDefaults.standard.set(true, forKey: completedKey)
                }
                isRunning = false
            }
        }
    }
}
