import XCTest
import CoreStore
@testable import Pilgrim

/// Transactionality tests for the tended-import replace path (audit U1):
/// `DataManager.replaceWalks` must delete the existing walk and insert the
/// tended version in ONE transaction, so a mid-write failure rolls the
/// store back to its pre-import state instead of leaving the originals
/// deleted with no replacement. Uses an in-memory CoreStore DataStack,
/// mirroring `PilgrimPackageImporterArchivedTests`.
final class PilgrimPackageImportTransactionTests: XCTestCase {

    private struct InjectedFailure: Error {}

    private var stack: DataStack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
    }

    override func tearDownWithError() throws {
        stack = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func seedWalk(
        uuid: UUID,
        comment: String = "original",
        recordings: [(startEpoch: Double, path: String)] = []
    ) throws {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= uuid
            walk._workoutType .= .walking
            walk._startDate .= Date(timeIntervalSince1970: 1_700_000_000)
            walk._endDate .= Date(timeIntervalSince1970: 1_700_001_800)
            walk._distance .= 3200
            walk._activeDuration .= 1800
            walk._pauseDuration .= 0
            walk._talkDuration .= 0
            walk._meditateDuration .= 0
            walk._ascend .= 10
            walk._descend .= 8
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"
            walk._comment .= comment

            for recording in recordings {
                let rec = transaction.create(Into<VoiceRecording>())
                rec._uuid .= UUID()
                rec._startDate .= Date(timeIntervalSince1970: recording.startEpoch)
                rec._endDate .= Date(timeIntervalSince1970: recording.startEpoch + 60)
                rec._duration .= 60
                rec._fileRelativePath .= recording.path
                rec._isEnhanced .= false
                rec._workout .= walk
            }
        })
    }

    private func replaceAndWait(
        _ objects: [WalkInterface]
    ) throws -> (success: Bool, walks: [Walk], replaced: Int, paths: [UUID: [String]]) {
        let done = expectation(description: "replaceWalks")
        var result: (Bool, [Walk], Int, [UUID: [String]]) = (false, [], 0, [:])
        DataManager.replaceWalks(objects: objects, dataStack: stack) { success, _, walks, replaced, paths in
            result = (success, walks, replaced, paths)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func fetchWalks(uuid: UUID) throws -> [Walk] {
        try stack.fetchAll(From<Walk>().where(\._uuid == uuid))
    }

    // MARK: - Happy path

    func test_replaceWalks_overwritesExistingWalk_inSingleTransaction() throws {
        let uuid = UUID()
        try seedWalk(uuid: uuid, comment: "original")

        let tended = WalkDataFactory.makeWalk(uuid: uuid, comment: "tended")
        let result = try replaceAndWait([tended])

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.replaced, 1)
        let walks = try fetchWalks(uuid: uuid)
        XCTAssertEqual(walks.count, 1, "replacement must not duplicate the walk")
        XCTAssertEqual(walks.first?._comment.value, "tended")
    }

    func test_replaceWalks_capturesRecordingPaths_inStartDateOrder() throws {
        let uuid = UUID()
        try seedWalk(uuid: uuid, recordings: [
            (startEpoch: 1_700_000_400, path: "Recordings/X/second.m4a"),
            (startEpoch: 1_700_000_100, path: "Recordings/X/first.m4a")
        ])

        let tended = WalkDataFactory.makeWalk(uuid: uuid, comment: "tended")
        let result = try replaceAndWait([tended])

        XCTAssertEqual(result.paths[uuid],
                       ["Recordings/X/first.m4a", "Recordings/X/second.m4a"],
                       "captured paths must be in startDate order for ordinal restore")
    }

    func test_replaceWalks_insertsWalk_whenNoUUIDMatch() throws {
        let uuid = UUID()

        let incoming = WalkDataFactory.makeWalk(uuid: uuid, comment: "fresh")
        let result = try replaceAndWait([incoming])

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.replaced, 0)
        XCTAssertTrue(result.paths.isEmpty)
        XCTAssertEqual(try fetchWalks(uuid: uuid).count, 1)
    }

    func test_replaceWalks_replacesOnlyMatchingUUIDs() throws {
        let replacedUUID = UUID()
        let untouchedUUID = UUID()
        let addedUUID = UUID()
        try seedWalk(uuid: replacedUUID, comment: "original")
        try seedWalk(uuid: untouchedUUID, comment: "bystander")

        let result = try replaceAndWait([
            WalkDataFactory.makeWalk(uuid: replacedUUID, comment: "tended"),
            WalkDataFactory.makeWalk(uuid: addedUUID, comment: "added")
        ])

        XCTAssertEqual(result.replaced, 1)
        XCTAssertEqual(result.walks.count, 2)
        XCTAssertEqual(try fetchWalks(uuid: replacedUUID).first?._comment.value, "tended")
        XCTAssertEqual(try fetchWalks(uuid: untouchedUUID).first?._comment.value, "bystander")
        XCTAssertEqual(try fetchWalks(uuid: addedUUID).count, 1)
    }

    // MARK: - Failure mid-write

    func test_replaceWalks_failureMidTransaction_leavesPreExistingWalksIntact() throws {
        let uuid = UUID()
        try seedWalk(uuid: uuid, comment: "original", recordings: [
            (startEpoch: 1_700_000_100, path: "Recordings/X/keep.m4a")
        ])

        let tended = WalkDataFactory.makeWalk(uuid: uuid, comment: "tended")

        let failed = expectation(description: "transaction failure")
        stack.perform(asynchronous: { transaction -> Bool in
            _ = try DataManager.replaceWalksInTransaction([tended], transaction: transaction)
            throw InjectedFailure()
        }, success: { _ in
            XCTFail("transaction must fail")
        }, failure: { _ in
            failed.fulfill()
        })
        wait(for: [failed], timeout: 5)

        let walks = try fetchWalks(uuid: uuid)
        XCTAssertEqual(walks.count, 1, "rollback must restore the original walk")
        let walk = try XCTUnwrap(walks.first)
        XCTAssertEqual(walk._comment.value, "original",
                       "the tended version must not survive a failed transaction")
        XCTAssertEqual(walk._voiceRecordings.value.map { $0._fileRelativePath.value },
                       ["Recordings/X/keep.m4a"],
                       "the original's recordings must survive the rollback")
    }
}
