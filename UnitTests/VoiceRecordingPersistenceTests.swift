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

    private func seedRecording(
        uuid: UUID, transcription: String? = nil, wordsPerMinute: Double? = nil,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws {
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
            recording._startDate .= startDate
            if let transcription { recording._transcription .= transcription }
            if let wordsPerMinute { recording._wordsPerMinute .= wordsPerMinute }
        })
    }

    private func seedWalk(
        uuid: UUID = UUID(), startDate: Date, comment: String? = nil,
        weatherCondition: String? = nil,
        routeSamples: [(timestamp: Date, lat: Double, lon: Double, accuracy: Double)] = []
    ) throws {
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= uuid
            walk._workoutType .= .walking
            walk._startDate .= startDate
            walk._endDate .= startDate.addingTimeInterval(1800)
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
            walk._dayIdentifier .= "20240615"
            if let comment { walk._comment .= comment }
            if let weatherCondition { walk._weatherCondition .= weatherCondition }
            for sample in routeSamples {
                let row = transaction.create(Into<RouteDataSample>())
                row._uuid .= UUID()
                row._timestamp .= sample.timestamp
                row._latitude .= sample.lat
                row._longitude .= sample.lon
                row._altitude .= 100
                row._horizontalAccuracy .= sample.accuracy
                row._verticalAccuracy .= 5
                row._speed .= 1.2
                row._direction .= 0
                row._workout .= walk
            }
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

    // MARK: - Analysis trigger (Threads)

    private func makeTranscriptContextStore() -> TranscriptContextStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceRecordingPersistenceTests-\(UUID().uuidString)")
        return TranscriptContextStore(directory: directory)
    }

    func test_updateTranscription_existingRecording_analyzesAndPersistsContext() throws {
        let uuid = UUID()
        try seedRecording(uuid: uuid)
        let contextStore = makeTranscriptContextStore()
        let transcript = "walked beneath the cedars this morning, still thinking about the move"

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingTranscription(
            uuid: uuid, transcription: transcript, transcriptContextStore: contextStore, dataStack: stack
        ) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        let deadline = Date().addingTimeInterval(5)
        while contextStore.context(for: uuid, matching: TranscriptContextStore.hash(of: transcript)) == nil,
              Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(
            contextStore.context(for: uuid, matching: TranscriptContextStore.hash(of: transcript)),
            "a successful, found update must analyze and persist a transcript context"
        )
    }

    func test_updateTranscription_existingRecording_threadsToggleOff_doesNotAnalyze() throws {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = false

        let uuid = UUID()
        try seedRecording(uuid: uuid)
        let contextStore = makeTranscriptContextStore()
        let transcript = "walked beneath the cedars this morning, still thinking about the move"

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingTranscription(
            uuid: uuid, transcription: transcript, transcriptContextStore: contextStore, dataStack: stack
        ) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        // Analysis is dispatched asynchronously on success only; give a
        // toggled-off update a beat to prove it never fires, rather than
        // asserting immediately against a task that was never scheduled.
        let notScheduled = expectation(description: "no analysis scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { notScheduled.fulfill() }
        wait(for: [notScheduled], timeout: 5)

        XCTAssertFalse(contextStore.hasContext(for: uuid), "toggle off must never analyze")
    }

    func test_updateTranscription_threadsToggleOff_removesStoredContext() throws {
        let saved = UserPreferences.threadsAfterWalks.value
        defer { UserPreferences.threadsAfterWalks.value = saved }
        UserPreferences.threadsAfterWalks.value = false

        let uuid = UUID()
        try seedRecording(uuid: uuid)
        let contextStore = makeTranscriptContextStore()
        contextStore.save(TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid,
            transcriptHash: TranscriptContextStore.hash(of: "the words before the edit"),
            languageCode: "en", wordCount: 5, themes: [], markers: nil
        ))

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingTranscription(
            uuid: uuid, transcription: "edited while the feature was off",
            transcriptContextStore: contextStore, dataStack: stack
        ) { success in
            XCTAssertTrue(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertFalse(contextStore.hasContext(for: uuid),
                       "an edit saved while the feature is off must not leave the old analysis to go stale")
        XCTAssertTrue(contextStore.save(TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: uuid,
            transcriptHash: TranscriptContextStore.hash(of: "edited while the feature was off"),
            languageCode: "en", wordCount: 6, themes: [], markers: nil
        )), "removal must not tombstone — the future backfill save has to succeed")
        XCTAssertTrue(contextStore.hasContext(for: uuid))
    }

    func test_updateTranscription_missingRecording_doesNotAnalyze() throws {
        let uuid = UUID()
        let contextStore = makeTranscriptContextStore()
        let transcript = "orphaned transcription for a recording that no longer exists"

        let done = expectation(description: "completion")
        DataManager.updateVoiceRecordingTranscription(
            uuid: uuid, transcription: transcript, transcriptContextStore: contextStore, dataStack: stack
        ) { success in
            XCTAssertFalse(success)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        // Analysis is dispatched asynchronously on success only; give a
        // vanished-row update a beat to prove it never fires, rather than
        // asserting immediately against a task that was never scheduled.
        let notScheduled = expectation(description: "no analysis scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { notScheduled.fulfill() }
        wait(for: [notScheduled], timeout: 5)

        XCTAssertFalse(contextStore.hasContext(for: uuid), "found == false must never analyze")
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

    // MARK: - Snapshot queries (Threads/Lunation) — dataStack is a static
    // default on these, not an injectable parameter, so swap-and-restore
    // DataManager.dataStack the way DataManagerThreadsDeletionTests does.

    @MainActor
    func test_transcribedRecordingsSnapshot_returnsTranscribedRecordings() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let uuid = UUID()
        try seedRecording(uuid: uuid, transcription: "walked beneath the cedars")

        let snapshot = DataManager.transcribedRecordingsSnapshot()

        XCTAssertEqual(snapshot.count, 1, "queryAttributes stores \"id\" as a string — a raw `as? UUID` cast must not silently drop every row")
        XCTAssertEqual(snapshot.first?.uuid, uuid)
        XCTAssertEqual(snapshot.first?.transcript, "walked beneath the cedars")
    }

    @MainActor
    func test_voiceRecordingPaceIndex_returnsWordsPerMinuteByRecording() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let uuid = UUID()
        try seedRecording(uuid: uuid, wordsPerMinute: 132.5)

        let index = DataManager.voiceRecordingPaceIndex()

        XCTAssertEqual(index.count, 1, "queryAttributes stores \"id\" as a string — a raw `as? UUID` cast must not silently drop every row")
        XCTAssertEqual(index[uuid] ?? -1, 132.5, accuracy: 0.001)
    }

    @MainActor
    func test_voiceRecordingWalkIndex_returnsOwningWalkByRecording() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let uuid = UUID()
        try seedRecording(uuid: uuid)
        let walk = try XCTUnwrap(try stack.fetchOne(From<VoiceRecording>().where(\._uuid == uuid))?._workout.value)

        let index = DataManager.voiceRecordingWalkIndex()

        XCTAssertEqual(index.count, 1, "queryAttributes stores \"id\" as a string — a raw `as? UUID` cast must not silently drop every row")
        XCTAssertEqual(index[uuid]?.walkUUID, walk._uuid.value)
        XCTAssertEqual(index[uuid]?.date, walk._startDate.value)
    }

    @MainActor
    func test_voiceRecordingTimestampIndex_returnsRecordingStartNotWalkStart() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let uuid = UUID()
        let recordingStart = Date(timeIntervalSince1970: 1_700_000_600)
        try seedRecording(uuid: uuid, startDate: recordingStart)

        let index = DataManager.voiceRecordingTimestampIndex()
        XCTAssertEqual(index[uuid], recordingStart,
                       "per-RECORDING instants — voiceRecordingWalkIndex's WALK dates cannot serve Track 1")
    }

    @MainActor
    func test_transcribedRecordingsSnapshot_rangeBoundsTheFetch() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let inside = UUID(), outside = UUID()
        try seedRecording(uuid: inside, transcription: "inside the window",
                          startDate: Date(timeIntervalSince1970: 1_700_000_000))
        try seedRecording(uuid: outside, transcription: "outside the window",
                          startDate: Date(timeIntervalSince1970: 1_600_000_000))

        let range = Date(timeIntervalSince1970: 1_699_999_000)...Date(timeIntervalSince1970: 1_700_001_000)
        let snapshot = DataManager.transcribedRecordingsSnapshot(in: range)
        XCTAssertEqual(snapshot.map(\.uuid), [inside])
        XCTAssertEqual(DataManager.transcribedRecordingsSnapshot().count, 2,
                       "nil range preserves the existing all-recordings behavior")
    }

    @MainActor
    func test_routeFixNear_returnsNearestSampleWithinNinetySeconds() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try seedWalk(startDate: target.addingTimeInterval(-600), routeSamples: [
            (target.addingTimeInterval(-80), 42.10, -8.50, 8),
            (target.addingTimeInterval(20), 42.20, -8.50, 12),
            (target.addingTimeInterval(70), 42.30, -8.50, 6)
        ])

        let fix = DataManager.routeFixNear(timestamp: target)
        XCTAssertEqual(fix?.coordinate.latitude ?? 0, 42.20, accuracy: 0.0001)
        XCTAssertEqual(fix?.gapSeconds ?? 0, 20, accuracy: 0.5)
        XCTAssertEqual(fix?.horizontalAccuracy ?? 0, 12, accuracy: 0.5)
    }

    @MainActor
    func test_routeFixNear_noSampleInWindow_returnsNil() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try seedWalk(startDate: target.addingTimeInterval(-600), routeSamples: [
            (target.addingTimeInterval(-120), 42.10, -8.50, 8)
        ])
        XCTAssertNil(DataManager.routeFixNear(timestamp: target),
                     "GPS-paused stretches and indoor starts never anchor a claim")
    }

    func test_routeFixNear_callableOffMain() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try seedWalk(startDate: target.addingTimeInterval(-600), routeSamples: [
            (target.addingTimeInterval(10), 42.10, -8.50, 8)
        ])
        let done = expectation(description: "off-main fix")
        DispatchQueue.global().async {
            let fix = DataManager.routeFixNear(timestamp: target)
            XCTAssertNotNil(fix, "the detached builder resolves fixes lazily — the main hop must hold")
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    @MainActor
    func test_walkSensesSnapshot_returnsIntentionWeatherAndBoundsRange() throws {
        let previousDataStack = DataManager.dataStack
        DataManager.dataStack = stack
        defer { DataManager.dataStack = previousDataStack }

        let inside = UUID()
        try seedWalk(uuid: inside, startDate: Date(timeIntervalSince1970: 1_700_000_000),
                     comment: "release what I cannot carry", weatherCondition: "lightRain")
        try seedWalk(startDate: Date(timeIntervalSince1970: 1_600_000_000), comment: "old walk")

        let rows = DataManager.walkSensesSnapshot(
            from: Date(timeIntervalSince1970: 1_699_000_000),
            to: Date(timeIntervalSince1970: 1_701_000_000)
        )
        XCTAssertEqual(rows.map(\.walkUUID), [inside],
                       "queryAttributes stores \"id\" as a string — rowUUID must decode it")
        XCTAssertEqual(rows.first?.intention, "release what I cannot carry")
        XCTAssertEqual(rows.first?.weatherCondition, "lightRain")
    }
}
