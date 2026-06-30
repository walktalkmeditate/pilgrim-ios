import XCTest
import CoreStore
@testable import Pilgrim

final class WalkSessionGuardRecoveryTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: WalkSessionGuard.checkpointFileURL())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: WalkSessionGuard.checkpointFileURL())
        DataManager.dataStack = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func writeCheckpointFixture(
        walkUUID: UUID = UUID(),
        voiceRecordings: [TempVoiceRecording] = []
    ) throws -> URL {
        let walk = WalkDataFactory.makeWalk(uuid: walkUUID, voiceRecordings: voiceRecordings)
        let checkpoint = WalkCheckpoint(walkUUID: walkUUID, walk: walk)
        let url = WalkSessionGuard.checkpointFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(checkpoint).write(to: url)
        return url
    }

    private func makeInMemoryStack() throws -> DataStack {
        let stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())
        return stack
    }

    // MARK: - Checkpoint lifecycle (AF1)

    func test_stop_preservesCheckpointFile() throws {
        let url = try writeCheckpointFixture()

        let guard_ = WalkSessionGuard()
        guard_.stop()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "stop() must leave the checkpoint for the save-confirmation path")
    }

    func test_stopAndCleanup_deletesCheckpointFile() throws {
        let url = try writeCheckpointFixture()

        let guard_ = WalkSessionGuard()
        guard_.stopAndCleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "user-discard path must remove the checkpoint")
    }

    func test_deleteCheckpointFile_removesFile() throws {
        let url = try writeCheckpointFixture()

        WalkSessionGuard.deleteCheckpointFile()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_saveSuccess_deletesCheckpoint_exactlyOnce() throws {
        DataManager.dataStack = try makeInMemoryStack()
        let previousContribute = UserPreferences.contributeToCollective.value
        UserPreferences.contributeToCollective.value = false
        defer { UserPreferences.contributeToCollective.value = previousContribute }

        let coordinator = MainCoordinator()
        coordinator.startWalk()
        let vm = try XCTUnwrap(coordinator.activeWalkViewModel)

        let url = try writeCheckpointFixture()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let snapshot = WalkDataFactory.makeWalk(uuid: UUID())
        vm.onWalkCompleted?(snapshot)

        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in coordinator.activeWalkViewModel == nil },
            object: nil
        )
        wait(for: [saved], timeout: 10)

        XCTAssertFalse(coordinator.showSaveError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "confirmed save must remove the checkpoint")
        let savedUUID = try XCTUnwrap(snapshot.uuid)
        XCTAssertNotNil(try DataManager.dataStack.fetchOne(
            From<Walk>().where(\._uuid == savedUUID)
        ))
    }

    func test_saveFailure_keepsCheckpoint_andSurfacesError() throws {
        let stack = try makeInMemoryStack()
        DataManager.dataStack = stack

        // A pre-existing walk with the same UUID makes saveWalk report
        // failure (duplicate filter) — a deterministic stand-in for any
        // failed save transaction.
        let duplicateUUID = UUID()
        try stack.perform(synchronous: { transaction in
            let walk = transaction.create(Into<Walk>())
            walk._uuid .= duplicateUUID
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
        })

        let coordinator = MainCoordinator()
        coordinator.startWalk()
        let vm = try XCTUnwrap(coordinator.activeWalkViewModel)

        let url = try writeCheckpointFixture(walkUUID: duplicateUUID)

        let snapshot = WalkDataFactory.makeWalk(uuid: duplicateUUID)
        vm.onWalkCompleted?(snapshot)

        let failed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in coordinator.showSaveError },
            object: nil
        )
        wait(for: [failed], timeout: 10)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "failed save must leave the checkpoint for launch recovery")

        coordinator.activeWalkViewModel = nil
    }

    // MARK: - Orphan sweep gate (AF2)

    func test_orphanSweepGate_waitsForBothSignals() {
        var sweeps = 0
        let gate = OrphanSweepGate { sweeps += 1 }

        gate.notePathRecoveryComplete()
        XCTAssertEqual(sweeps, 0, "path recovery alone must not trigger the sweep")

        gate.noteWalkRecoveryResolved()
        XCTAssertEqual(sweeps, 1)
    }

    func test_orphanSweepGate_sweepsExactlyOnce_regardlessOfSignalOrderAndRepeats() {
        var sweeps = 0
        let gate = OrphanSweepGate { sweeps += 1 }

        gate.noteWalkRecoveryResolved()
        XCTAssertEqual(sweeps, 0, "recovery alone must not trigger the sweep")

        gate.notePathRecoveryComplete()
        gate.notePathRecoveryComplete()
        gate.noteWalkRecoveryResolved()
        XCTAssertEqual(sweeps, 1)
    }

    func test_recoverIfNeeded_resolvesGate_whenNoCheckpointExists() throws {
        DataManager.dataStack = try makeInMemoryStack()

        var sweeps = 0
        let gate = OrphanSweepGate { sweeps += 1 }
        gate.notePathRecoveryComplete()

        let done = expectation(description: "recovery completion")
        WalkSessionGuard.recoverIfNeeded(sweepGate: gate) { date in
            XCTAssertNil(date)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(sweeps, 1, "no checkpoint → sweep must not starve")
    }

    // MARK: - Recovery + sweep ordering (AF2 integration)

    func test_crashedWalkRecovery_commitsBeforeSweep_audioSurvives() throws {
        let stack = try makeInMemoryStack()
        DataManager.dataStack = stack

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let walkUUID = UUID()
        let staleUUID = UUID()
        let walkDir = docs.appendingPathComponent("Recordings/\(walkUUID.uuidString)")
        let staleDir = docs.appendingPathComponent("Recordings/\(staleUUID.uuidString)")
        try fm.createDirectory(at: walkDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: staleDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: walkDir)
            try? fm.removeItem(at: staleDir)
        }

        let recFile = walkDir.appendingPathComponent("rec.m4a")
        let staleFile = staleDir.appendingPathComponent("stale.m4a")
        try Data("crashed-walk-audio".utf8).write(to: recFile)
        try Data("stale-orphan".utf8).write(to: staleFile)

        // Non-nil recording UUID = finalized (not provisional), so recovery
        // trusts the checkpoint instead of probing the fake audio bytes.
        let recording = WalkDataFactory.makeVoiceRecording(
            uuid: UUID(),
            fileRelativePath: "Recordings/\(walkUUID.uuidString)/rec.m4a"
        )
        _ = try writeCheckpointFixture(walkUUID: walkUUID, voiceRecordings: [recording])

        let sweepDone = expectation(description: "sweep completed")
        let gate = OrphanSweepGate {
            OrphanRecordingSweep.run { sweepDone.fulfill() }
        }
        gate.notePathRecoveryComplete()

        let recoveryDone = expectation(description: "recovery completed")
        var recoveredDate: Date?
        WalkSessionGuard.recoverIfNeeded(sweepGate: gate) { date in
            recoveredDate = date
            recoveryDone.fulfill()
        }
        wait(for: [recoveryDone, sweepDone], timeout: 10)

        XCTAssertNotNil(recoveredDate, "crashed walk must be recovered")
        XCTAssertNotNil(try stack.fetchOne(From<Walk>().where(\._uuid == walkUUID)),
                        "recovered walk must be committed to the store")
        XCTAssertTrue(fm.fileExists(atPath: recFile.path),
                      "recovered walk's audio must survive the sweep")
        XCTAssertFalse(fm.fileExists(atPath: staleFile.path),
                       "genuinely orphaned audio must still be swept")
        XCTAssertFalse(fm.fileExists(atPath: WalkSessionGuard.checkpointFileURL().path),
                       "checkpoint must be removed after the recovery commit")
    }

    func test_checkpointVoiceRecording_snapshot_can_be_appended_to_checkpoint() {
        let vm = ActiveWalkViewModel()
        let builder = vm.builder

        vm.voiceRecordingManagement._test_setActiveRecording(
            start: Date(timeIntervalSinceNow: -42),
            relativePath: "Recordings/DEADBEEF/rec.m4a"
        )

        builder._test_setStartDate(Date(timeIntervalSinceNow: -60))

        let snapshot = builder.createCheckpointSnapshot()
        XCTAssertNotNil(snapshot)

        if let inflight = vm.voiceRecordingManagement.checkpointVoiceRecording() {
            snapshot?.appendVoiceRecordings([inflight])
        }

        XCTAssertEqual(snapshot?.voiceRecordings.count, 1)
        XCTAssertEqual(snapshot?.voiceRecordings.first?.fileRelativePath,
                       "Recordings/DEADBEEF/rec.m4a")
        XCTAssertEqual(snapshot?.voiceRecordings.first?.duration ?? 0, 42, accuracy: 1.0)
    }

    func test_sanitizeUnplayableRecordings_clearsPath_forMoovLessFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WalkSessionGuardRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let brokenFile = tmpDir.appendingPathComponent("broken.m4a")
        try Data().write(to: brokenFile)

        let recording = TempVoiceRecording(
            uuid: nil,
            startDate: Date(timeIntervalSinceNow: -30),
            endDate: Date(),
            duration: 30,
            fileRelativePath: "ignored/broken.m4a",
            isEnhanced: false
        )

        let sanitized = WalkSessionGuard.sanitizeRecording(
            recording,
            fileURL: brokenFile
        )
        XCTAssertEqual(sanitized.fileRelativePath, "")
        XCTAssertEqual(sanitized.duration, 30, accuracy: 0.1,
                       "duration must be preserved for the Talk timer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenFile.path),
                       "unplayable file must be removed from disk")
    }

    func test_sanitizeUnplayableRecordings_preservesPath_whenFilePlayable() throws {
        let playable = TempVoiceRecording(
            uuid: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(5),
            duration: 5,
            fileRelativePath: "Recordings/ABC/rec.m4a",
            isEnhanced: false
        )

        let sanitized = WalkSessionGuard.sanitizeRecording(
            playable,
            fileURL: nil,
            durationProbe: { _ in 5.0 }
        )
        XCTAssertEqual(sanitized.fileRelativePath, "Recordings/ABC/rec.m4a")
    }

    func test_sanitizeUnplayableRecordings_preservesPath_whenProbeReportsPositive() {
        let recording = TempVoiceRecording(
            uuid: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(5),
            duration: 5,
            fileRelativePath: "Recordings/ABC/rec.m4a",
            isEnhanced: false
        )
        let fakeURL = URL(fileURLWithPath: "/does/not/exist.m4a")

        let sanitized = WalkSessionGuard.sanitizeRecording(
            recording,
            fileURL: fakeURL,
            durationProbe: { _ in 5.0 }
        )

        XCTAssertEqual(sanitized.fileRelativePath, "Recordings/ABC/rec.m4a")
    }

    func test_defaultDurationProbe_readsDuration_fromPlayableFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(UUID().uuidString).wav")
        try TestAudioFile.writeSilentAudioFile(to: url, duration: 3.0)
        defer { try? FileManager.default.removeItem(at: url) }

        let seconds = WalkSessionGuard.defaultDurationProbe(url)

        XCTAssertEqual(seconds, 3.0, accuracy: 0.1)
    }

    func test_defaultDurationProbe_returnsZero_forMissingOrCorruptFile() throws {
        let missing = URL(fileURLWithPath: "/does/not/exist.m4a")
        XCTAssertEqual(WalkSessionGuard.defaultDurationProbe(missing), 0)

        let corrupt = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }

        XCTAssertEqual(WalkSessionGuard.defaultDurationProbe(corrupt), 0)
    }
}
