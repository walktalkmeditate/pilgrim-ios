import XCTest
@testable import Pilgrim

/// Stands in for a loaded WhisperKit model; model-load tests only care
/// about lifecycle, never about transcription output.
private final class FakeEngine: TranscriptionEngine {
    func transcribeAudio(atPath path: String) async throws -> TranscriptionOutput {
        TranscriptionOutput(text: "", wordsPerMinute: nil)
    }
    func unloadModels() async {}
}

/// Thread-safe call counter — the injected engine loader runs on
/// cooperative-pool threads, so bookkeeping needs its own lock.
private final class LoadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func recordLoad() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// AF31: `ensureModelReady` must be single-flight. The post-walk
/// auto-transcription batch and VoiceCard's settings toggle can reach it
/// concurrently; without the gate both would load WhisperKit and race on
/// the engine reference.
final class TranscriptionServiceModelLoadTests: XCTestCase {

    func testConcurrentEnsureModelReady_loadsModelOnce() async throws {
        let recorder = LoadRecorder()
        let service = TranscriptionService(engineLoader: {
            _ = recorder.recordLoad()
            try await Task.sleep(nanoseconds: 100_000_000)
            return FakeEngine()
        })

        async let first: Void = service.ensureModelReady()
        async let second: Void = service.ensureModelReady()
        async let third: Void = service.ensureModelReady()
        _ = try await (first, second, third)

        XCTAssertEqual(recorder.loadCount, 1, "concurrent callers must share a single model load")
        let loaded = await service._test_isModelLoaded
        XCTAssertTrue(loaded, "all callers must proceed with the shared engine loaded")
    }

    func testEnsureModelReady_whenAlreadyLoaded_doesNotReload() async throws {
        let recorder = LoadRecorder()
        let service = TranscriptionService(engineLoader: {
            _ = recorder.recordLoad()
            return FakeEngine()
        })

        try await service.ensureModelReady()
        try await service.ensureModelReady()

        XCTAssertEqual(recorder.loadCount, 1, "a loaded engine must satisfy later calls without reloading")
    }

    func testFailedLoad_surfacesErrorAndClearsGateForRetry() async throws {
        let recorder = LoadRecorder()
        let service = TranscriptionService(engineLoader: {
            if recorder.recordLoad() == 1 {
                throw NSError(domain: "TranscriptionServiceModelLoadTests", code: 1)
            }
            return FakeEngine()
        })

        do {
            try await service.ensureModelReady()
            XCTFail("first load must surface its error")
        } catch {}

        let loadedAfterFailure = await service._test_isModelLoaded
        XCTAssertFalse(loadedAfterFailure, "a failed load must not leave an engine behind")

        try await service.ensureModelReady()

        XCTAssertEqual(recorder.loadCount, 2, "a failed load must clear the gate so the next call retries")
        let loaded = await service._test_isModelLoaded
        XCTAssertTrue(loaded)
    }

    @MainActor
    func testUnloadModel_thenEnsureModelReady_reloads() async throws {
        let recorder = LoadRecorder()
        let service = TranscriptionService(engineLoader: {
            _ = recorder.recordLoad()
            return FakeEngine()
        })

        try await service.ensureModelReady()
        XCTAssertTrue(service._test_isModelLoaded)

        service.unloadModel()
        XCTAssertFalse(service._test_isModelLoaded)

        try await service.ensureModelReady()

        XCTAssertEqual(recorder.loadCount, 2, "unloadModel must clear the gate coherently so the next call reloads")
        XCTAssertTrue(service._test_isModelLoaded)
    }
}
