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
}
