import XCTest
import CoreStore
@testable import Pilgrim

/// AF26/AF38: the voice-recording persistence updaters must report
/// success/failure to their callers instead of swallowing errors —
/// `false` covers both a failed transaction and a recording row that no
/// longer exists (e.g. replaced by a concurrent tended import).
final class VoiceRecordingPersistenceTests: XCTestCase {

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

    private func seedRecording(uuid: UUID) throws {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= UUID()
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
            recording._uuid .= uuid
            recording._fileRelativePath .= "Recordings/X/a.m4a"
            recording._workout .= walk
        })
    }

    private func fetchRecording(uuid: UUID) throws -> VoiceRecording? {
        try stack.fetchOne(From<VoiceRecording>().where(\._uuid == uuid))
    }

    // MARK: - Transcription (AF26)

    func test_updateTranscription_existingRecording_reportsSuccess_andPersists() throws {
        let uuid = UUID()
        try seedRecording(uuid: uuid)

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingTranscription(
            uuid: uuid, transcription: "walked beneath the cedars", dataStack: stack
        ) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(try fetchRecording(uuid: uuid)?._transcription.value, "walked beneath the cedars")
    }

    func test_updateTranscription_missingRecording_reportsFailure() throws {
        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingTranscription(
            uuid: UUID(), transcription: "orphan", dataStack: stack
        ) { success in
            XCTAssertFalse(success, "a vanished row must not be reported as saved")
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    // MARK: - Words per minute (AF26)

    func test_updateWordsPerMinute_existingRecording_reportsSuccess_andPersists() throws {
        let uuid = UUID()
        try seedRecording(uuid: uuid)

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingWordsPerMinute(
            uuid: uuid, wordsPerMinute: 132.5, dataStack: stack
        ) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(try XCTUnwrap(fetchRecording(uuid: uuid)?._wordsPerMinute.value), 132.5, accuracy: 0.001)
    }

    // MARK: - isEnhanced (AF38)

    func test_updateIsEnhanced_existingRecording_reportsSuccess_andPersists() throws {
        let uuid = UUID()
        try seedRecording(uuid: uuid)

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingIsEnhanced(
            uuid: uuid, isEnhanced: true, dataStack: stack
        ) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(try fetchRecording(uuid: uuid)?._isEnhanced.value, true)
    }

    func test_updateIsEnhanced_missingRecording_reportsFailure() throws {
        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingIsEnhanced(
            uuid: UUID(), isEnhanced: true, dataStack: stack
        ) { success in
            XCTAssertFalse(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
