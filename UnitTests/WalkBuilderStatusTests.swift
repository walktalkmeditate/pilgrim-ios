import XCTest
import Combine
@testable import Pilgrim

private class TestComponent: WalkBuilderComponent {
    required init(builder: WalkBuilder) {}
    func bind(builder: WalkBuilder) {}
}

final class WalkBuilderStatusTests: XCTestCase {

    // MARK: - Status Transitions

    func testInitialStatus_isWaiting() {
        let builder = WalkBuilder()
        XCTAssertEqual(builder.status, .waiting)
    }

    func testWaitingToRecording_rejected() {
        let builder = WalkBuilder()
        builder.setStatus(.recording)
        XCTAssertEqual(builder.status, .waiting)
    }

    func testReadyToRecording_accepted() {
        let builder = WalkBuilder()
        builder.setStatus(.ready)
        builder.setStatus(.recording)
        XCTAssertEqual(builder.status, .recording)
    }

    func testRecordingToPaused_accepted() {
        let builder = WalkBuilder()
        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.paused)
        XCTAssertEqual(builder.status, .paused)
    }

    func testRecordingToAutoPaused_accepted() {
        let builder = WalkBuilder()
        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.autoPaused)
        XCTAssertEqual(builder.status, .autoPaused)
    }

    func testPausedToRecording_accepted() {
        let builder = WalkBuilder()
        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.paused)
        builder.setStatus(.recording)
        XCTAssertEqual(builder.status, .recording)
    }

    func testPausedToAutoPaused_rejected() {
        let builder = WalkBuilder()
        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.paused)
        builder.setStatus(.autoPaused)
        XCTAssertEqual(builder.status, .paused)
    }

    // MARK: - Component Readiness

    func testComponentReadiness_preparingThenReady_becomesReady() {
        let builder = WalkBuilder()
        let readinessSubject = PassthroughSubject<WalkBuilderComponentStatus, Never>()
        let input = WalkBuilder.Input(readiness: readinessSubject.eraseToAnyPublisher())
        let _ = builder.tranform(input)

        readinessSubject.send(.preparing(TestComponent.self))
        XCTAssertEqual(builder.status, .waiting)

        readinessSubject.send(.ready(TestComponent.self))
        XCTAssertEqual(builder.status, .ready)
    }

    // MARK: - Pause Creation

    func testPauseCreatedOnResumeFromPaused() {
        let builder = WalkBuilder()
        var latestPauses: [TempWalkPause] = []
        let cancellable = builder.pausesPublisher.sink { latestPauses = $0 }
        defer { cancellable.cancel() }

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.paused)
        builder.setStatus(.recording)

        XCTAssertEqual(latestPauses.count, 1)
        XCTAssertEqual(latestPauses.first?.pauseType, .manual)
    }

    func testShortAutoPause_discarded() {
        let builder = WalkBuilder()
        var latestPauses: [TempWalkPause] = []
        let cancellable = builder.pausesPublisher.sink { latestPauses = $0 }
        defer { cancellable.cancel() }

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.autoPaused)
        builder.setStatus(.recording)

        XCTAssertEqual(latestPauses.count, 0)
    }

    func testLongAutoPause_kept() {
        let builder = WalkBuilder()
        var latestPauses: [TempWalkPause] = []
        let cancellable = builder.pausesPublisher.sink { latestPauses = $0 }
        defer { cancellable.cancel() }

        builder.setStatus(.ready)
        builder.setStatus(.recording)
        builder.setStatus(.autoPaused)
        Thread.sleep(forTimeInterval: 3.5)
        builder.setStatus(.recording)

        XCTAssertEqual(latestPauses.count, 1)
        XCTAssertEqual(latestPauses.first?.pauseType, .automatic)
    }

    func testConsecutiveSameTypePauses_merged() {
        let builder = WalkBuilder()
        var latestPauses: [TempWalkPause] = []
        let cancellable = builder.pausesPublisher.sink { latestPauses = $0 }
        defer { cancellable.cancel() }

        builder.setStatus(.ready)
        builder.setStatus(.recording)

        builder.setStatus(.paused)
        builder.setStatus(.recording)
        let firstPauseStart = latestPauses.first!.startDate

        builder.setStatus(.paused)
        builder.setStatus(.recording)

        XCTAssertEqual(latestPauses.count, 2)
        XCTAssertEqual(latestPauses.last?.startDate, firstPauseStart)
    }
}
