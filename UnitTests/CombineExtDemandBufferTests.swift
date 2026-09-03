import Combine
import CombineExt
import XCTest
@testable import Pilgrim

/// Guards the Podfile's CombineExt patch. Unpatched, `DemandBuffer` reads
/// its `completion` outside the lock and traps when a value lands after a
/// cancel — the shape of ending a walk while a location sample is still
/// crossing the shared background queue. A trap here fails the whole run,
/// which is the point: this must never regress silently.
final class CombineExtDemandBufferTests: XCTestCase {

    func testCancellingARelayWhileAnotherThreadFloodsItNeverTraps() {
        for round in 0..<40 {
            let relay = CurrentValueRelay<Int>(0)
            var received = 0
            var cancellable: AnyCancellable? = relay
                .asBackgroundPublisher()
                .sink { _ in received += 1 }
            let flood = expectation(description: "flood \(round)")
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 1...20_000 { relay.accept(i) }
                flood.fulfill()
            }
            // Cancel mid-flood, from another thread than the producer.
            usleep(UInt32.random(in: 50...500))
            cancellable?.cancel()
            cancellable = nil
            wait(for: [flood], timeout: 10)
            _ = received
        }
    }

    func testAValueAfterCompletionIsDroppedNotTrapped() {
        let relay = PassthroughRelay<Int>()
        var values: [Int] = []
        let cancellable = relay.sink { values.append($0) }
        relay.accept(1)
        cancellable.cancel()
        relay.accept(2)
        XCTAssertEqual(values, [1])
    }
}
