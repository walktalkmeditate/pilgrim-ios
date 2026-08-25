import Foundation

/// One-time pass over already-transcribed recordings when the feature first
/// activates — origin claims ("first time", "where it began") are only true
/// once history is fully analyzed (spec: ThreadStore).
enum ThreadsBackfill {

    static let completedKey = "threadsBackfillCompletedV4"
    /// v1.11.0 TestFlight devices could run the sweep, account for zero
    /// recordings under a snapshot bug (fixed alongside the V2 rename), and
    /// still set the old flag — stranding those devices on a never-swept
    /// history forever, since `runIfNeeded` guards on `!isComplete`. Build
    /// 106 devices completed a real V2 sweep, but ThemeExtractor's raw
    /// verb-inclusive filter let spoken scaffolding ("was", "have", "can",
    /// "think") win every theme ranking — those stored themes are junk, not
    /// stale. Build 108 devices completed a real V3 sweep with the
    /// noun-only extractor, but nothing checked `TranscriptContext
    /// .schemaVersion` — a bare `hasContext` skip treated existence as
    /// freshness, so verb/adjective scaffolding and stoplisted nouns that
    /// had already been stored under V2 survived the V3 "re-arm" untouched.
    /// Each rename re-arms by construction: the new key is absent, so
    /// `isComplete` reads false regardless of what any old key holds — V4
    /// additionally makes freshness itself schema-version-aware end to end
    /// (see docs/solutions/derived-cache-semantics-are-schema.md).
    private static let legacyCompletedKeyV3 = "threadsBackfillCompletedV3"
    private static let legacyCompletedKeys = [
        "threadsBackfillCompleted", "threadsBackfillCompletedV2", legacyCompletedKeyV3
    ]
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

    /// The one entry point for the settings toggle: the preference flip and
    /// the enable-path resweep belong together. The resweep is scheduled as
    /// a task so it lands after the caller's UI transaction commits instead
    /// of running the CoreStore snapshot inside the toggle animation.
    @MainActor
    static func setEnabled(_ enabled: Bool) {
        UserPreferences.threadsAfterWalks.value = enabled
        guard enabled else { return }
        reset()
        Task { @MainActor in runIfNeeded() }
    }

    static let batchSize = 25

    /// One-time hygiene ahead of the `isComplete` check below: the pre-V4
    /// keys no longer mean anything, and removing an absent key is a
    /// harmless no-op on every call after the first. The V3 key's presence
    /// — captured before removal — is also the moon-line re-arm signal
    /// (item 2): only a device that completed the stale-theme V3 sweep ever
    /// had a moon line burned on junk themes, so only that device's budget
    /// clears. A fresh install or an already-migrated device (V3 key
    /// already gone) leaves the moon key untouched.
    private static func performLegacyHygiene() {
        let hadV3Key = UserDefaults.standard.object(forKey: legacyCompletedKeyV3) != nil
        legacyCompletedKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        guard hadV3Key else { return }
        UserDefaults.standard.removeObject(forKey: ThreadsDossierBuilder.moonLineDefaultsKey)
    }

    /// Stale-schema files whose recording isn't in this sweep's snapshot are
    /// deleted outright: `loadAll`/`ThreadsDossierBuilder`'s own orphan
    /// cleanup only ever sees current-schema contexts, so a stale orphan
    /// would otherwise linger on disk forever, invisible to every reader
    /// yet never pruned. `store.delete` tombstones them, matching the
    /// builder's own orphan-cleanup path.
    ///
    /// An empty `liveUUIDs` is skipped outright: `transcribedRecordingsSnapshot`
    /// silently returns `[]` on any CoreStore failure (`try? queryAttributes`),
    /// indistinguishable here from a genuinely empty history. Treating it as
    /// proof of orphanhood would store-wide delete every stale-schema context
    /// still on disk for recordings that are, in fact, live — mirroring the
    /// sibling guard in `ThreadsDossierBuilder.build()`
    /// (`walkIndex.isEmpty && !all.isEmpty`). A genuine zero-recording device
    /// has nothing worth pruning anyway, so the skip costs nothing real.
    private static func pruneStaleOrphans(store: TranscriptContextStore, liveUUIDs: Set<UUID>) {
        guard !liveUUIDs.isEmpty else { return }
        let staleOrphans = store.loadAllIncludingStaleVersions()
            .filter { $0.schemaVersion != TranscriptContext.currentSchemaVersion && !liveUUIDs.contains($0.recordingUUID) }
            .map(\.recordingUUID)
        guard !staleOrphans.isEmpty else { return }
        store.delete(recordingUUIDs: staleOrphans)
    }

    /// Main-actor only: the CoreStore snapshot must be taken before
    /// detaching — `dataStack` queries assert main-thread. Single-flight,
    /// and battery-gated like MainCoordinator.triggerAutoTranscription.
    /// Fills MISSING contexts only: a hash-mismatched (edited) recording is
    /// owned by the edit trigger, and overwriting it here would race a
    /// newer analysis with this launch's stale snapshot.
    ///
    /// The completed flag is set only when every snapshot item is accounted
    /// for — saved by this sweep, or already on disk after the attempt.
    /// A failed save (or the battery gate / toggle closing mid-sweep) leaves
    /// the flag false so the next launch retries just the missing ones.
    ///
    /// Off means no analysis at all, not just no surfacing — mid-sweep the
    /// per-batch guard re-checks the toggle, and re-enabling resweeps via
    /// `setEnabled(true)`. A reset landing mid-sweep (import, re-enable)
    /// makes this sweep stale; its completion then schedules one follow-up
    /// pass — a cheap hasCurrentContext-only resweep — so the session
    /// doesn't end with the flag stuck false.
    ///
    /// `snapshotProvider`, `gate`, and `onFinish` are test seams; production
    /// callers use the defaults, which preserve the shipped behavior exactly.
    @MainActor
    static func runIfNeeded(
        store: TranscriptContextStore = .shared,
        snapshotProvider: @escaping @MainActor () -> [(uuid: UUID, transcript: String)] = {
            DataManager.transcribedRecordingsSnapshot()
        },
        gate: @escaping @MainActor () -> Bool = { BatteryGate.allowsBackgroundWork() },
        onFinish: (@MainActor () -> Void)? = nil
    ) {
        performLegacyHygiene()
        guard !isComplete, !isRunning, UserPreferences.threadsAfterWalks.value, gate() else {
            onFinish?()
            return
        }
        isRunning = true

        let startGeneration = generation
        let items = snapshotProvider()
        Task.detached(priority: .utility) {
            pruneStaleOrphans(store: store, liveUUIDs: Set(items.map(\.uuid)))
            var allAccounted = true
            var gateClosed = false
            var batchStart = 0
            while batchStart < items.count {
                guard await MainActor.run(body: { gate() && UserPreferences.threadsAfterWalks.value }) else {
                    gateClosed = true
                    break
                }
                let batch = items[batchStart..<min(batchStart + batchSize, items.count)]
                for item in batch where !store.hasCurrentContext(for: item.uuid) {
                    let saved = TranscriptContextAnalyzer.analyzeAndStore(
                        recordingUUID: item.uuid,
                        transcript: item.transcript,
                        store: store
                    ).saved
                    if !saved && !store.hasCurrentContext(for: item.uuid) {
                        allAccounted = false
                    }
                }
                batchStart += batchSize
                await Task.yield()
            }
            await MainActor.run {
                let stale = generation != startGeneration
                if !stale && allAccounted && !gateClosed {
                    UserDefaults.standard.set(true, forKey: completedKey)
                }
                isRunning = false
                if stale {
                    Task { @MainActor in
                        runIfNeeded(store: store, snapshotProvider: snapshotProvider, gate: gate, onFinish: onFinish)
                    }
                }
                onFinish?()
            }
        }
    }
}
