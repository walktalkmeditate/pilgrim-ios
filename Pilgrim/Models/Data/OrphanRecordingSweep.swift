import Foundation
import CoreStore

enum OrphanRecordingSweep {

    /// One-shot at app launch. Enumerates all .m4a files under the Recordings
    /// directory, matches each by its path relative to Documents against the
    /// active set of VoiceRecording entities, and deletes any that are not
    /// referenced. Errors are logged but never thrown — this is best-effort
    /// cleanup that catches files left behind by failed post-archive deletion
    /// (Task 4) or any walk-delete path that did not clean up its files.
    static func run() {
        DataManager.dataStack.perform(asynchronous: { transaction in
            try collectReferencedRelativePaths(in: transaction)
        }, success: { referenced in
            sweepFiles(notMatching: referenced)
        }, failure: { error in
            print("[OrphanRecordingSweep] CoreStore fetch failed: \(error)")
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

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "m4a" {
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
