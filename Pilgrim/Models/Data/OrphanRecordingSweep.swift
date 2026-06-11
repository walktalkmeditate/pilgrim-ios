import Foundation
import CoreStore

/// Serializes the launch cleanup chain: the orphan sweep deletes any audio
/// file not referenced by a VoiceRecording row, so it must not run until
/// (a) `RecordingPathRecovery` has back-filled empty paths AND (b) a crashed
/// walk's checkpoint recovery has committed its rows — otherwise the sweep
/// would delete the very recordings recovery is about to reference (AF2).
///
/// `WalkSessionGuard.recoverIfNeeded` runs from MainCoordinator, which never
/// constructs during onboarding/migration sessions. To avoid sweep
/// starvation there, AppDelegate resolves the recovery dependency
/// immediately when no checkpoint file exists. When a checkpoint exists but
/// its recovery save fails, the gate intentionally never opens this session
/// — skipping a sweep is safe; sweeping pre-commit is not.
final class OrphanSweepGate {

    static let shared = OrphanSweepGate { OrphanRecordingSweep.run() }

    private let sweep: () -> Void
    private var pathRecoveryComplete = false
    private var walkRecoveryResolved = false
    private var sweepStarted = false

    init(sweep: @escaping () -> Void) {
        self.sweep = sweep
    }

    func notePathRecoveryComplete() {
        onMain {
            self.pathRecoveryComplete = true
            self.runIfReady()
        }
    }

    /// "Resolved" means no checkpoint blocks the sweep: recovery committed,
    /// the checkpoint was discarded, or none existed in the first place.
    func noteWalkRecoveryResolved() {
        onMain {
            self.walkRecoveryResolved = true
            self.runIfReady()
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func runIfReady() {
        guard pathRecoveryComplete, walkRecoveryResolved, !sweepStarted else { return }
        sweepStarted = true
        sweep()
    }
}

enum OrphanRecordingSweep {

    /// One-shot at app launch. Enumerates all .m4a files under the Recordings
    /// directory, matches each by its path relative to Documents against the
    /// active set of VoiceRecording entities, and deletes any that are not
    /// referenced. Errors are logged but never thrown — this is best-effort
    /// cleanup that catches files left behind by failed post-archive deletion
    /// (Task 4) or any walk-delete path that did not clean up its files.
    static func run(completion: (() -> Void)? = nil) {
        DataManager.dataStack.perform(asynchronous: { transaction in
            try collectReferencedRelativePaths(in: transaction)
        }, success: { referenced in
            sweepFiles(notMatching: referenced)
            completion?()
        }, failure: { error in
            print("[OrphanRecordingSweep] CoreStore fetch failed: \(error)")
            completion?()
        })
    }

    private static func collectReferencedRelativePaths(
        in transaction: AsynchronousDataTransaction
    ) throws -> Set<String> {
        let recordings: [VoiceRecording] = try transaction.fetchAll(From<VoiceRecording>())
        return Set(recordings.map { $0._fileRelativePath.value })
    }

    private static func sweepFiles(notMatching referenced: Set<String>) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        let fm = FileManager.default

        guard fm.fileExists(atPath: recordingsDir.path) else { return }

        guard let enumerator = fm.enumerator(at: recordingsDir, includingPropertiesForKeys: nil) else {
            print("[OrphanRecordingSweep] could not enumerate \(recordingsDir.path)")
            return
        }

        let audioExtensions: Set<String> = ["m4a", "wav"]
        for case let fileURL as URL in enumerator where audioExtensions.contains(fileURL.pathExtension.lowercased()) {
            guard let relativePath = relativePath(of: fileURL, from: docs) else { continue }
            guard !referenced.contains(relativePath) else { continue }

            do {
                try fm.removeItem(at: fileURL)
                print("[OrphanRecordingSweep] removed orphan: \(relativePath)")
            } catch {
                print("[OrphanRecordingSweep] could not remove \(relativePath): \(error)")
            }
        }
    }

    private static func relativePath(of url: URL, from base: URL) -> String? {
        let filePath = url.path
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard filePath.hasPrefix(basePath) else { return nil }
        return String(filePath.dropFirst(basePath.count))
    }
}
