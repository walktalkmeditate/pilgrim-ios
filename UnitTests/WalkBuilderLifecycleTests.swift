import XCTest
import Combine
@testable import Pilgrim

/// Positive control for ApplicationStateObservation dispatch: proves
/// `stateChanged` actually delivered while a deallocated builder did not.
private final class ProbeStateObserver: ApplicationStateObserver {
    private(set) var received: [ApplicationState] = []
    func didUpdateApplicationState(to state: ApplicationState) {
        received.append(state)
    }
}

/// Stands in for a loaded WhisperKit model so batch-lifecycle behavior is
/// testable without downloading or loading a real CoreML pipeline.
private final class FakeTranscriptionEngine: TranscriptionEngine {

    private(set) var transcribeCallCount = 0
    var onUnload: (() -> Void)?

    func transcribeAudio(atPath path: String) async throws -> TranscriptionOutput {
        transcribeCallCount += 1
        throw NSError(domain: "FakeTranscriptionEngine", code: 1)
    }

    func unloadModels() async {
        onUnload?()
    }
}

final class WalkBuilderLifecycleTests: XCTestCase {

    /// CoreLocation delivers authorization/state callbacks asynchronously and
    /// holds an autoreleased strong reference to the delegate until they land,
    /// so component deallocation is eventual, not immediate. Spin the main run
    /// loop until the object is gone (or the timeout proves a leak).
    private func assertEventuallyDeallocated(
        _ name: String,
        timeout: TimeInterval = 2.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ object: () -> AnyObject?
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while object() != nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNil(object(), "\(name) leaked", file: file, line: line)
    }

    // MARK: - AF8: completed walk releases the builder graph

    func testCompletedWalk_builderAndComponentsDeallocate() {
        weak var weakBuilder: WalkBuilder?
        weak var weakLocation: LocationManagement?
        weak var weakSteps: StepCounter?

        autoreleasepool {
            var builder: WalkBuilder? = WalkBuilder()
            var location: LocationManagement? = LocationManagement(builder: builder!)
            var steps: StepCounter? = StepCounter(builder: builder!)
            weakBuilder = builder
            weakLocation = location
            weakSteps = steps
            settleCombineSchedulers()

            builder?.setStatus(.ready)
            builder?.setStatus(.recording)
            builder?.setStatus(.ready)
            settleCombineSchedulers()

            builder = nil
            location = nil
            steps = nil
        }

        assertEventuallyDeallocated("WalkBuilder") { weakBuilder }
        assertEventuallyDeallocated("LocationManagement") { weakLocation }
        assertEventuallyDeallocated("StepCounter") { weakSteps }
    }

    // MARK: - AF8: cancelled walk releases builder, route data, and observer slot

    func testCancelledWalk_builderDeallocatesAndRouteDataReleased() {
        weak var weakBuilder: WalkBuilder?
        weak var weakSample: TempRouteDataSample?
        var builderID: ObjectIdentifier!

        autoreleasepool {
            var builder: WalkBuilder? = WalkBuilder()
            var location: LocationManagement? = LocationManagement(builder: builder!)
            var steps: StepCounter? = StepCounter(builder: builder!)
            weakBuilder = builder
            builderID = ObjectIdentifier(builder!)
            settleCombineSchedulers()

            builder?.setStatus(.ready)
            builder?.setStatus(.recording)

            var sample: TempRouteDataSample? = WalkDataFactory.makeRouteDataSample()
            weakSample = sample
            builder?.flushLocations([sample!], distance: 12)
            sample = nil

            XCTAssertNotNil(
                ApplicationStateObservation.observations[builderID],
                "recording builder must be registered for app-state callbacks"
            )

            // Cancelled walks never pass through .ready/reset() — the owner
            // just drops its references (MainCoordinator.cancelWalk).
            builder = nil
            location = nil
            steps = nil
            settleCombineSchedulers()
        }

        assertEventuallyDeallocated("WalkBuilder") { weakBuilder }
        assertEventuallyDeallocated("route data of a cancelled walk") { weakSample }

        let probe = ProbeStateObserver()
        ApplicationStateObservation.addObserver(probe)
        defer { ApplicationStateObservation.removeObserver(probe) }
        ApplicationStateObservation.stateChanged(to: .foreground)

        XCTAssertEqual(probe.received, [.foreground], "state change must still reach live observers")
        XCTAssertNil(
            ApplicationStateObservation.observations[builderID],
            "deallocated builder must be purged from app-state observations"
        )
    }

    // MARK: - AF33: auto-transcription batch drain releases the model

    @MainActor
    func testAutoTranscriptionBatchDrained_releasesModel() async throws {
        let service = TranscriptionService()
        let engine = FakeTranscriptionEngine()
        let unloaded = expectation(description: "engine unloadModels called")
        engine.onUnload = { unloaded.fulfill() }
        service._test_setEngine(engine)

        // Deliberately outside Documents/recordings — the app host's
        // OrphanRecordingSweep owns that directory and would race this file.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let relativePath = "lifecycle-test-\(UUID().uuidString).m4a"
        let audioURL = docs.appendingPathComponent(relativePath)
        try TestAudioFile.writeSilentAudioFile(to: audioURL, duration: 0.2)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let recording = WalkDataFactory.makeVoiceRecording(
            uuid: UUID(),
            fileRelativePath: relativePath,
            transcription: nil
        )

        _ = await service.transcribeRecordings([recording])

        XCTAssertEqual(engine.transcribeCallCount, 1, "batch must have reached the engine")
        XCTAssertFalse(service._test_isModelLoaded, "model must be released when the batch drains")
        XCTAssertEqual(service.state, .completed, "unload must not clobber the terminal state")
        await fulfillment(of: [unloaded], timeout: 2.0)
    }

    @MainActor
    func testUnloadModel_keepsModelDuringActiveBatch() {
        let service = TranscriptionService()
        service._test_setEngine(FakeTranscriptionEngine())
        service.state = .completed

        service._test_setTranscribing(true)
        service.unloadModel()
        XCTAssertTrue(service._test_isModelLoaded, "model must stay resident during an active batch")

        service._test_setTranscribing(false)
        service.unloadModel()
        XCTAssertFalse(service._test_isModelLoaded)
        XCTAssertEqual(service.state, .completed, "unload must not reset the published state")
    }
}
