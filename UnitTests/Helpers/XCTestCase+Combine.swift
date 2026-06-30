import XCTest
import Combine

extension XCTestCase {

    /// Spins the main run loop once so scheduled Combine bookkeeping lands.
    ///
    /// Subscriptions built over `receive(on: DispatchQueue.main)` enqueue
    /// their upstream demand requests asynchronously. A test that constructs
    /// and tears down a WalkBuilder pipeline without ever yielding leaves
    /// those subscriptions demand-less, and CombineExt's CurrentValueRelay
    /// deinit then traps on DemandBuffer's double-completion precondition
    /// (a pending completion that can never flush). Call this after building
    /// the object graph in any fast test that owns builder components.
    func settleCombineSchedulers() {
        let exp = expectation(description: "combine schedulers settled")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    func awaitPublisher<P: Publisher>(
        _ publisher: P,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> P.Output {
        var result: Result<P.Output, Error>?
        let exp = expectation(description: "Awaiting publisher")

        let cancellable = publisher
            .first()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        result = .failure(error)
                    }
                    exp.fulfill()
                },
                receiveValue: { value in
                    result = .success(value)
                }
            )

        waitForExpectations(timeout: timeout)
        cancellable.cancel()

        let unwrapped = try XCTUnwrap(result, "Publisher did not produce output", file: file, line: line)
        return try unwrapped.get()
    }

    func collectValues<P: Publisher>(
        from publisher: P,
        count: Int,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> [P.Output] {
        var values: [P.Output] = []
        let exp = expectation(description: "Collecting \(count) values")

        let cancellable = publisher
            .prefix(count)
            .sink(
                receiveCompletion: { _ in exp.fulfill() },
                receiveValue: { values.append($0) }
            )

        waitForExpectations(timeout: timeout)
        cancellable.cancel()

        XCTAssertEqual(values.count, count, file: file, line: line)
        return values
    }
}
