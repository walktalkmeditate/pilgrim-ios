import Foundation
import UIKit

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

    /// Main-actor only: the CoreStore snapshot must be taken before
    /// detaching — `dataStack.fetchAll` asserts main-thread. Single-flight,
    /// and battery-gated like MainCoordinator.triggerAutoTranscription.
    /// Fills MISSING contexts only: a hash-mismatched (edited) recording is
    /// owned by the edit trigger, and overwriting it here would race a
    /// newer analysis with this launch's stale snapshot.
    @MainActor
    static func runIfNeeded(store: TranscriptContextStore = .shared) {
        guard !isComplete, !isRunning else { return }
        let wasMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        UIDevice.current.isBatteryMonitoringEnabled = wasMonitoring
        guard level < 0 || level > 0.2 || batteryState == .charging || batteryState == .full else { return }
        isRunning = true

        let startGeneration = generation
        let items = DataManager.transcribedRecordingsSnapshot()
        Task.detached(priority: .utility) {
            for item in items where !store.hasContext(for: item.uuid) {
                TranscriptContextAnalyzer.analyzeAndStore(
                    recordingUUID: item.uuid,
                    transcript: item.transcript,
                    store: store
                )
            }
            await MainActor.run {
                if generation == startGeneration {
                    UserDefaults.standard.set(true, forKey: completedKey)
                }
                isRunning = false
            }
        }
    }
}
