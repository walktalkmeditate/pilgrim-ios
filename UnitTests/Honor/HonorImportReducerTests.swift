import XCTest
@testable import Pilgrim

final class HonorImportReducerTests: XCTestCase {

    func testTransitions() {
        let id = "share:abc"
        XCTAssertEqual(HonorImportReducer.state(wayId: id, progress: [id: 0.4], active: [id], failures: [:], diskFull: []),
                       .gathering(progress: 0.4))
        XCTAssertEqual(HonorImportReducer.state(wayId: id, progress: [id: 1], active: [], failures: [:], diskFull: []), .ready)
        XCTAssertEqual(HonorImportReducer.state(wayId: id, progress: [id: 1], active: [], failures: [id: ["audio/2.m4a"]], diskFull: []),
                       .mediaMissing(["audio/2.m4a"]))
        XCTAssertEqual(HonorImportReducer.state(wayId: id, progress: [:], active: [id], failures: [:], diskFull: [id]),
                       .failed(.diskFull), "disk full outranks everything")
    }

    func testCopyNamesEveryFailure() {
        XCTAssertEqual(HonorImportCopy.line(for: .failed(.diskFull)), "not enough space on this phone to save these voices")
        XCTAssertNotNil(HonorImportCopy.line(for: .failed(.notFound)))
        XCTAssertNil(HonorImportCopy.line(for: .ready))
    }

    func testCopyGatheringRoundsToWholePercent() {
        XCTAssertEqual(HonorImportCopy.line(for: .gathering(progress: 0.456)), "gathering their voices · 46%")
    }

    func testCopyMediaMissing() {
        XCTAssertEqual(HonorImportCopy.line(for: .mediaMissing(["audio/2.m4a"])), "some voices didn't arrive")
    }

    func testCopyIdleIsSilent() {
        XCTAssertNil(HonorImportCopy.line(for: .idle))
    }
}
