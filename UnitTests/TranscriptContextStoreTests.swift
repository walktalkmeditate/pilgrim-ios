import XCTest
@testable import Pilgrim

final class TranscriptContextStoreTests: XCTestCase {

    private var store: TranscriptContextStore!
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptContextsTests-\(UUID().uuidString)")
        store = TranscriptContextStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeContext(uuid: UUID = UUID(), transcript: String = "hello world") -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid,
            transcriptHash: TranscriptContextStore.hash(of: transcript),
            languageCode: "en",
            wordCount: 2,
            themes: [],
            markers: nil
        )
    }

    func testSaveAndLoadRoundTrip() {
        let context = makeContext(transcript: "the river again")
        store.save(context)
        let loaded = store.context(
            for: context.recordingUUID,
            matching: TranscriptContextStore.hash(of: "the river again")
        )
        XCTAssertEqual(loaded, context)
    }

    func testHashMismatch_returnsNil() {
        let context = makeContext(transcript: "original words")
        store.save(context)
        XCTAssertNil(store.context(
            for: context.recordingUUID,
            matching: TranscriptContextStore.hash(of: "edited words")
        ))
    }

    func testDeleteByUUIDs() {
        let a = makeContext(), b = makeContext()
        store.save(a); store.save(b)
        store.delete(recordingUUIDs: [a.recordingUUID])
        XCTAssertEqual(store.loadAll().map(\.recordingUUID), [b.recordingUUID])
    }

    func testDeleteAll() {
        store.save(makeContext()); store.save(makeContext())
        store.deleteAll()
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testSaveAfterDelete_doesNotResurrect() {
        let context = makeContext()
        store.save(context)
        store.delete(recordingUUIDs: [context.recordingUUID])
        store.save(context)
        XCTAssertTrue(store.loadAll().isEmpty,
                      "a queued analysis landing after deletion must not resurrect derived data")
    }

    func testSaveAfterDelete_reportsAccountedWithoutWriting() {
        let context = makeContext()
        store.save(context)
        store.delete(recordingUUIDs: [context.recordingUUID])
        XCTAssertTrue(store.save(context),
                      "a tombstone-blocked save is deliberately accounted for, not a failure")
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testSave_reportsWriteFailure() throws {
        let readOnly = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadOnlyStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
            try? FileManager.default.removeItem(at: readOnly)
        }
        let readOnlyStore = TranscriptContextStore(directory: readOnly)
        XCTAssertFalse(readOnlyStore.save(makeContext()),
                       "a context that never reached disk must not be reported as saved")
    }

    func testClearTombstones_scopedToGivenUUIDs() {
        let imported = makeContext(), unrelated = makeContext()
        store.save(imported); store.save(unrelated)
        store.delete(recordingUUIDs: [imported.recordingUUID, unrelated.recordingUUID])
        store.clearTombstones(for: [imported.recordingUUID])
        store.save(imported)
        store.save(unrelated)
        XCTAssertEqual(store.loadAll().map(\.recordingUUID), [imported.recordingUUID],
                       "an import re-establishes its own recordings as analyzable — "
                       + "tombstones protecting unrelated pending deletions stay in force")
    }

    func testRemoveContext_deletesWithoutTombstoning() {
        let context = makeContext()
        store.save(context)
        store.removeContext(for: context.recordingUUID)
        XCTAssertFalse(store.hasContext(for: context.recordingUUID))
        store.save(context)
        XCTAssertEqual(store.loadAll().map(\.recordingUUID), [context.recordingUUID],
                       "no tombstone: the future backfill save must still succeed")
    }

    func testOrphans_pureSelectionOverLoadedContexts() {
        let keep = makeContext(), orphan = makeContext()
        let orphans = TranscriptContextStore.orphans(
            in: [keep, orphan], keeping: [keep.recordingUUID]
        )
        XCTAssertEqual(orphans, [orphan.recordingUUID])
    }

    func testDirectoryExcludedFromBackup() throws {
        store.save(makeContext())
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    private func makeStaleContext(uuid: UUID = UUID(), transcript: String = "stale analysis") -> TranscriptContext {
        TranscriptContext(
            schemaVersion: 1,
            recordingUUID: uuid,
            transcriptHash: TranscriptContextStore.hash(of: transcript),
            languageCode: "en",
            wordCount: 2,
            themes: [],
            markers: nil
        )
    }

    func testLoadAll_excludesStaleSchemaVersion() {
        let stale = makeStaleContext()
        let fresh = makeContext()
        store.save(stale)
        store.save(fresh)
        XCTAssertEqual(store.loadAll().map(\.recordingUUID), [fresh.recordingUUID],
                       "a stale-schema context must be invisible to every reader — threads, dossier, suggestions")
    }

    func testLoadAllIncludingStaleVersions_includesEveryVersion() {
        let stale = makeStaleContext()
        let fresh = makeContext()
        store.save(stale)
        store.save(fresh)
        XCTAssertEqual(Set(store.loadAllIncludingStaleVersions().map(\.recordingUUID)),
                       Set([stale.recordingUUID, fresh.recordingUUID]),
                       "the sweep's stale-orphan cleanup needs every stored version, not just current")
    }

    func testHasCurrentContext_falseForStaleSchemaVersion() {
        let stale = makeStaleContext()
        store.save(stale)
        XCTAssertFalse(store.hasCurrentContext(for: stale.recordingUUID),
                       "a stale-schema file on disk must not count as current")
        XCTAssertTrue(store.hasContext(for: stale.recordingUUID),
                      "existence still true — only freshness differs")
    }

    /// The v1.11 shipped schema. Its themes were computed by an extractor
    /// that admitted conversational filler and let a swallowed sentence
    /// period fork one word into two lemmas, so a v4 file on disk is stale by
    /// derivation even though it decodes cleanly
    /// (docs/solutions/derived-cache-semantics-are-schema.md).
    func testHasCurrentContext_falseForSchemaVersionFour() {
        let context = TranscriptContext(
            schemaVersion: 4, recordingUUID: UUID(), transcriptHash: "v4",
            languageCode: "en", wordCount: 2, themes: [], markers: nil
        )
        store.save(context)
        XCTAssertFalse(store.hasCurrentContext(for: context.recordingUUID),
                       "the filler/punctuation fix makes every v4-derived context stale")
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testHasCurrentContext_trueForCurrentSchemaVersion() {
        let fresh = makeContext()
        store.save(fresh)
        XCTAssertTrue(store.hasCurrentContext(for: fresh.recordingUUID))
    }

    func testHasCurrentContext_falseWhenMissing() {
        XCTAssertFalse(store.hasCurrentContext(for: UUID()))
    }
}
