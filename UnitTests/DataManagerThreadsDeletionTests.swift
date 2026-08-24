import XCTest
import CoreStore
@testable import Pilgrim

/// Deletion is the trigger for transcript-context cleanup, not luck: a
/// single-walk delete and Delete All Data must both remove the derived
/// context files alongside the recordings they came from.
final class DataManagerThreadsDeletionTests: XCTestCase {

    private var stack: DataStack!
    private var store: TranscriptContextStore!
    private var directory: URL!
    private var previousDataStack: DataStack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousDataStack = DataManager.dataStack
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        DataManager.dataStack = stack

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadsDeletionTests-\(UUID().uuidString)")
        store = TranscriptContextStore(directory: directory)
        DataManager.transcriptContextStore = store
    }

    override func tearDownWithError() throws {
        DataManager.transcriptContextStore = .shared
        DataManager.dataStack = previousDataStack
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func context(for uuid: UUID) -> TranscriptContext {
        TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid, transcriptHash: "h", languageCode: "en",
            wordCount: 2, themes: [], markers: nil
        )
    }

    private func seedWalkWithTranscribedRecording() throws -> (walk: Walk, recordingUUID: UUID) {
        let walkUUID = UUID()
        let recordingUUID = UUID()

        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= walkUUID
            walk._workoutType .= .walking
            walk._startDate .= Date(timeIntervalSince1970: 1_700_000_000)
            walk._endDate .= Date(timeIntervalSince1970: 1_700_001_800)
            walk._distance .= 1000
            walk._activeDuration .= 1800
            walk._pauseDuration .= 0
            walk._talkDuration .= 0
            walk._meditateDuration .= 0
            walk._ascend .= 0
            walk._descend .= 0
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"

            let recording = transaction.create(Into<VoiceRecording>())
            recording._uuid .= recordingUUID
            recording._fileRelativePath .= "Recordings/X/a.m4a"
            recording._workout .= walk
        })

        let walk = try XCTUnwrap(stack.fetchOne(From<Walk>().where(\._uuid == walkUUID)))
        return (walk, recordingUUID)
    }

    func testDeleteWalk_removesItsRecordingContexts() throws {
        let (walk, recordingUUID) = try seedWalkWithTranscribedRecording()
        store.save(context(for: recordingUUID))

        let deleted = expectation(description: "deleted")
        DataManager.deleteObject(object: walk) { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertFalse(store.hasContext(for: recordingUUID))
    }

    func testDeleteAll_removesEveryContextFile() throws {
        let (_, recordingUUID) = try seedWalkWithTranscribedRecording()
        store.save(context(for: recordingUUID))
        store.save(context(for: UUID()))

        let deleted = expectation(description: "deleted all")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testDeleteAll_tombstonesRecordingsWithoutContextFiles() throws {
        let (_, recordingUUID) = try seedWalkWithTranscribedRecording()

        let deleted = expectation(description: "deleted all")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)

        store.save(context(for: recordingUUID))
        XCTAssertTrue(store.loadAll().isEmpty,
                      "an analysis queued before Delete All must not write after the wipe")
    }

    func testDeleteAll_clearsReleasedThreads() {
        let suiteName = "ReleasedThreadsDeleteAll-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let released = ReleasedThreadsStore(defaults: defaults)
        released.release(displayTerm: "the move", lemmas: ["move"])
        DataManager.releasedThreadsStore = released
        defer { DataManager.releasedThreadsStore = .shared }

        let deleted = expectation(description: "deleted all")
        DataManager.deleteAll { success, _ in
            XCTAssertTrue(success)
            deleted.fulfill()
        }
        wait(for: [deleted], timeout: 5)
        XCTAssertTrue(released.isEmpty, "Delete All Data clears the released set with everything else")
    }
}
