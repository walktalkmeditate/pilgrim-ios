import XCTest
import CoreStore
@testable import Pilgrim

/// AF27: `PilgrimPackageBuilder.build` must distinguish a database fetch
/// failure from a store that genuinely contains no walks. Export is the
/// app's disaster-recovery path — telling a user with hundreds of walks
/// "no walks found" during a transient DB error would be alarming and
/// would hide the real failure.
final class PilgrimPackageBuilderErrorTests: XCTestCase {

    func test_emptyStore_reportsNoWalksFound() throws {
        let stack = DataStack(PilgrimV7.schema)
        try stack.addStorageAndWait(InMemoryStore())

        let done = expectation(description: "build")
        PilgrimPackageBuilder.build(dataStack: stack) { result in
            guard case .failure(.noWalksFound) = result else {
                XCTFail("an empty store must report .noWalksFound, got \(result)")
                return done.fulfill()
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func test_fetchFailure_reportsDatabaseError_notNoWalksFound() {
        // A stack with the right schema but no storage attached makes the
        // walk fetch throw CoreStoreError.persistentStoreNotFound inside
        // the transaction — a deterministic stand-in for a database error.
        let stack = DataStack(PilgrimV7.schema)

        let done = expectation(description: "build")
        PilgrimPackageBuilder.build(dataStack: stack) { result in
            switch result {
            case .failure(.databaseError):
                break
            case .failure(.noWalksFound):
                XCTFail("a fetch failure must not masquerade as an empty store")
            default:
                XCTFail("unexpected result: \(result)")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
