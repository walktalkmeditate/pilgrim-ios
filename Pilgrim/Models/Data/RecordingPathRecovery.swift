import Foundation
import CoreStore

/// One-shot at app launch (paired with `OrphanRecordingSweep`). Finds
/// VoiceRecording rows with empty `_fileRelativePath` — typically left
/// behind by a tended `.pilgrim` import that round-tripped through a format
/// which doesn't carry per-recording paths — and back-fills them from the
/// .m4a/.wav files still on disk under `Recordings/<walkUUID>/`.
///
/// Match heuristic: per walk, sort orphaned files by creation date and
/// VoiceRecording rows by `startDate` and assign 1:1. Order is the only
/// stable signal once the path is gone — file UUIDs in the filename are
/// independent of the entity UUIDs in CoreStore. Idempotent: skips
/// recordings whose path is already populated, so safe to run every launch.
enum RecordingPathRecovery {

    static func run(completion: (() -> Void)? = nil) {
        DataManager.dataStack.perform(asynchronous: { transaction -> Int in
            try recoverPaths(in: transaction)
        }, success: { recovered in
            if recovered > 0 {
                print("[RecordingPathRecovery] restored \(recovered) recording paths")
            }
            completion?()
        }, failure: { error in
            print("[RecordingPathRecovery] CoreStore fetch failed: \(error)")
            completion?()
        })
    }

    private static func recoverPaths(
        in transaction: AsynchronousDataTransaction
    ) throws -> Int {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsRoot = docs.appendingPathComponent("Recordings")
        let fm = FileManager.default

        guard fm.fileExists(atPath: recordingsRoot.path) else { return 0 }

        let walks: [Walk] = try transaction.fetchAll(From<Walk>())
        var recoveredCount = 0

        for walk in walks {
            guard let walkUUID = walk._uuid.value else { continue }

            let orphans = walk._voiceRecordings.value
                .filter { $0._fileRelativePath.value.isEmpty }
                .sorted { $0._startDate.value < $1._startDate.value }
            guard !orphans.isEmpty else { continue }

            let walkDir = recordingsRoot.appendingPathComponent(walkUUID.uuidString)
            guard let candidates = audioFiles(in: walkDir, fm: fm), !candidates.isEmpty else {
                continue
            }

            let referencedPaths = Set(walk._voiceRecordings.value
                .map { $0._fileRelativePath.value }
                .filter { !$0.isEmpty })
            let unreferenced = candidates.filter { url in
                let rel = "Recordings/\(walkUUID.uuidString)/\(url.lastPathComponent)"
                return !referencedPaths.contains(rel)
            }
            guard !unreferenced.isEmpty else { continue }

            let sortedFiles = unreferenced.sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lDate < rDate
            }

            for (idx, recording) in orphans.enumerated() {
                guard idx < sortedFiles.count else { break }
                guard let editable = transaction.edit(recording) else { continue }
                let rel = "Recordings/\(walkUUID.uuidString)/\(sortedFiles[idx].lastPathComponent)"
                editable._fileRelativePath .= rel
                recoveredCount += 1
            }
        }

        return recoveredCount
    }

    private static func audioFiles(in dir: URL, fm: FileManager) -> [URL]? {
        guard fm.fileExists(atPath: dir.path) else { return nil }
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.filter { ["m4a", "wav"].contains($0.pathExtension.lowercased()) }
    }
}
