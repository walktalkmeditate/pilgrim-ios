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
    private var _changeCount = 0

    var changeCount: Int { writeQueue.sync { _changeCount } }

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
    ///
    /// Returns true when the context is accounted for — written to disk, or
    /// deliberately blocked by a tombstone. False only on encode/write
    /// failure, so callers (the backfill) know the item is still missing.
    @discardableResult
    func save(_ context: TranscriptContext) -> Bool {
        writeQueue.sync {
            guard !tombstones.contains(context.recordingUUID) else { return true }
            guard let data = try? JSONEncoder().encode(context) else { return false }
            do {
                try data.write(to: fileURL(for: context.recordingUUID), options: .atomic)
            } catch {
                return false
            }
            _changeCount += 1
            return true
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

    /// Existence AND freshness — unlike `hasContext`, a stale-schema file on
    /// disk answers false, so the backfill sweep re-analyzes it instead of
    /// skipping it. `hasContext` stays a bare existence check for callers
    /// that only care whether something was written (self-heal
    /// confirmation, deletion assertions).
    func hasCurrentContext(for recordingUUID: UUID) -> Bool {
        load(recordingUUID: recordingUUID)?.schemaVersion == TranscriptContext.currentSchemaVersion
    }

    /// Every reader (threads/dossier/suggestions) sees only current-schema
    /// contexts — a stale-derivation file left on disk by an older build
    /// must be invisible, not merely outdated.
    func loadAll() -> [TranscriptContext] {
        loadAllIncludingStaleVersions()
            .filter { $0.schemaVersion == TranscriptContext.currentSchemaVersion }
    }

    /// Unfiltered by schema version — for the backfill sweep's stale-orphan
    /// cleanup, which needs to see every stored version to find files
    /// `loadAll` deliberately hides.
    func loadAllIncludingStaleVersions() -> [TranscriptContext] {
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
            _changeCount += 1
        }
    }

    /// Tombstones without touching files — for Delete All, which follows up
    /// with `deleteAll()` for the file sweep (and its changeCount bump).
    /// The insert-before-wipe ordering is the late-write protection: an
    /// analysis queued before the wipe finds its UUID blocked afterward.
    func insertTombstones(for uuids: [UUID]) {
        writeQueue.sync {
            tombstones.formUnion(uuids)
        }
    }

    /// Removes a stored context without tombstoning — for edits made while
    /// the feature is off, where the old analysis must not linger stale. A
    /// tombstone here would block the future backfill save for this
    /// recording and corrupt its accounting (a blocked save reports
    /// "accounted" while writing nothing).
    func removeContext(for recordingUUID: UUID) {
        writeQueue.sync {
            try? FileManager.default.removeItem(at: fileURL(for: recordingUUID))
            _changeCount += 1
        }
    }

    /// Import success clears the imported recordings' tombstones only: the
    /// import re-establishes those UUIDs as live data that must be
    /// analyzable, while tombstones protecting unrelated pending deletions
    /// stay in force.
    func clearTombstones(for uuids: [UUID]) {
        writeQueue.sync {
            tombstones.subtract(uuids)
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
            _changeCount += 1
        }
        excludeFromBackup()
    }

    /// Pure orphan selection over already-loaded contexts — the caller
    /// (ThreadsDossierBuilder) feeds it the same load that builds the
    /// dossier, so no second directory read happens here.
    static func orphans(in contexts: [TranscriptContext], keeping valid: Set<UUID>) -> [UUID] {
        contexts.map(\.recordingUUID).filter { !valid.contains($0) }
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
