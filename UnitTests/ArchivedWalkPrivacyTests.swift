import XCTest
import CoreStore
@testable import Pilgrim

/// Programmatic acceptance test for the archive privacy contract:
/// after importing an archived entry whose walk exists in CoreStore,
/// the walk's recording files and route data must be absent on disk
/// and in the database.
final class ArchivedWalkPrivacyTests: XCTestCase {

    private var stack: DataStack!
    private var recordingURLs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        UserPreferences.archivedWalkRegistry.value = [:]
    }

    override func tearDownWithError() throws {
        stack = nil
        for url in recordingURLs {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURLs.removeAll()
        UserPreferences.archivedWalkRegistry.value = [:]
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeRecordingFile(relativePath: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fake audio".utf8).write(to: url)
        recordingURLs.append(url)
        return url
    }

    private func seedWalk(uuid: UUID, recordingRelativePath: String, withRoute: Bool = true) throws {
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
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"

            let rec = transaction.create(Into<VoiceRecording>())
            rec._uuid .= UUID()
            rec._startDate .= Date(timeIntervalSince1970: 1_700_000_100)
            rec._endDate .= Date(timeIntervalSince1970: 1_700_000_160)
            rec._duration .= 60
            rec._fileRelativePath .= recordingRelativePath
            rec._transcription .= "test"
            rec._isEnhanced .= false
            rec._workout .= walk

            if withRoute {
                let sample = transaction.create(Into<RouteDataSample>())
                sample._uuid .= UUID()
                sample._latitude .= 48.8566
                sample._longitude .= 2.3522
                sample._altitude .= 35
                sample._timestamp .= Date(timeIntervalSince1970: 1_700_000_050)
                sample._horizontalAccuracy .= 5
                sample._verticalAccuracy .= 3
                sample._speed .= 1.4
                sample._direction .= 90
                sample._workout .= walk
            }
        })
    }

    private func applyAndWait(archived: [PilgrimArchivedWalk]) throws {
        let expectation = XCTestExpectation(description: "applyArchivedEntries")
        var capturedError: Error?
        PilgrimPackageImporter.applyArchivedEntries(archived, dataStack: stack) { result in
            if case .failure(let err) = result { capturedError = err }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        if let err = capturedError { throw err }
    }

    // MARK: - Tests

    func testHeavyDataDeletionAfterImport() throws {
        let uuid = UUID()
        let relPath = "Recordings/privacy-test-\(uuid.uuidString)/walk.m4a"
        let fileURL = try makeRecordingFile(relativePath: relPath)

        try seedWalk(uuid: uuid, recordingRelativePath: relPath, withRoute: true)

        let walkBefore = try XCTUnwrap(
            stack.fetchOne(From<Walk>().where(\._uuid == uuid))
        )
        XCTAssertFalse(walkBefore._routeData.value.isEmpty, "Precondition: walk has route data")
        XCTAssertFalse(walkBefore._voiceRecordings.value.isEmpty, "Precondition: walk has recordings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Precondition: audio file exists on disk")

        let payload = ArchivedWalkFixtures.archivedWalk(id: uuid)
        try applyAndWait(archived: [payload])

        let walkAfter = try XCTUnwrap(
            stack.fetchOne(From<Walk>().where(\._uuid == uuid))
        )
        XCTAssertTrue(walkAfter._routeData.value.isEmpty, "routeData must be stripped post-archive")
        XCTAssertTrue(walkAfter._voiceRecordings.value.isEmpty, "voiceRecordings must be stripped post-archive")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "Audio file must be deleted from disk post-archive"
        )
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid), "Walk must be registered in archive sidecar")
    }

    func testAudioFileDeletionDoesNotThrowOnMissingFile() throws {
        let uuid = UUID()
        let relPath = "Recordings/nonexistent-\(uuid.uuidString)/walk.m4a"

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
            walk._isRace .= false
            walk._isUserModified .= false
            walk._finishedRecording .= true
            walk._dayIdentifier .= "20231115"

            let rec = transaction.create(Into<VoiceRecording>())
            rec._uuid .= UUID()
            rec._startDate .= Date(timeIntervalSince1970: 1_700_000_100)
            rec._endDate .= Date(timeIntervalSince1970: 1_700_000_160)
            rec._duration .= 60
            rec._fileRelativePath .= relPath
            rec._isEnhanced .= false
            rec._workout .= walk
        })

        let payload = ArchivedWalkFixtures.archivedWalk(id: uuid)
        XCTAssertNoThrow(try applyAndWait(archived: [payload]),
            "Missing audio file must not cause the import to throw")
        XCTAssertTrue(UserPreferences.isArchivedWalk(uuid: uuid),
            "Registry must still be updated even if file deletion fails")
    }
}
