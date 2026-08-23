import Foundation
import CryptoKit

/// File-per-recording JSON store under Application Support, excluded from
/// backups — derived psychological data is recomputable and must not ride
/// along in iCloud/iTunes backups (spec: Storage).
final class TranscriptContextStore {

    static let shared = TranscriptContextStore(
        directory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TranscriptContexts", isDirectory: true)
    )

    private let directory: URL
    private let writeQueue = DispatchQueue(label: "org.walktalkmeditate.pilgrim.transcript-contexts")
    private var tombstones: Set<UUID> = []
    private(set) var changeCount = 0

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup()
    }

    static func hash(of transcript: String) -> String {
        SHA256.hash(data: Data(transcript.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Deleted UUIDs are tombstoned so a queued analysis finishing after a
    /// deletion cannot resurrect derived data. Stale writes self-heal: any
    /// consumer that finds a hash mismatch re-analyzes and persists.
    func save(_ context: TranscriptContext) {
        writeQueue.sync {
            guard !tombstones.contains(context.recordingUUID),
                  let data = try? JSONEncoder().encode(context) else { return }
            try? data.write(to: fileURL(for: context.recordingUUID), options: .atomic)
            changeCount += 1
        }
    }

    func context(for recordingUUID: UUID, matching transcriptHash: String) -> TranscriptContext? {
        guard let loaded = load(recordingUUID: recordingUUID),
              loaded.transcriptHash == transcriptHash,
              loaded.schemaVersion == TranscriptContext.currentSchemaVersion else { return nil }
        return loaded
    }

    func hasContext(for recordingUUID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: recordingUUID).path)
    }

    func loadAll() -> [TranscriptContext] {
        contextFileURLs()
            .compactMap { try? JSONDecoder().decode(TranscriptContext.self, from: Data(contentsOf: $0)) }
            .sorted { $0.recordingUUID.uuidString < $1.recordingUUID.uuidString }
    }

    func delete(recordingUUIDs: [UUID]) {
        writeQueue.sync {
            for uuid in recordingUUIDs {
                tombstones.insert(uuid)
                try? FileManager.default.removeItem(at: fileURL(for: uuid))
            }
            changeCount += 1
        }
    }

    func deleteAll() {
        writeQueue.sync {
            for url in contextFileURLs() {
                UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                    .map { tombstones.insert($0) }
            }
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                print("[TranscriptContextStore] Failed to remove context directory: \(error)")
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            changeCount += 1
        }
        excludeFromBackup()
    }

    func pruneOrphans(keeping valid: Set<UUID>) {
        let orphans = loadAll().map(\.recordingUUID).filter { !valid.contains($0) }
        guard !orphans.isEmpty else { return }
        delete(recordingUUIDs: orphans)
    }

    private func contextFileURLs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    private func load(recordingUUID: UUID) -> TranscriptContext? {
        guard let data = try? Data(contentsOf: fileURL(for: recordingUUID)) else { return nil }
        return try? JSONDecoder().decode(TranscriptContext.self, from: data)
    }

    private func fileURL(for uuid: UUID) -> URL {
        directory.appendingPathComponent("\(uuid.uuidString).json")
    }

    private func excludeFromBackup() {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
