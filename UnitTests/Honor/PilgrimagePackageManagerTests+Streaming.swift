import XCTest
@testable import Pilgrim

/// What the package fetch does when the response will not say how long it is,
/// and when the CDN answers with anything but 200. Cases of
/// `PilgrimagePackageManagerTests` (its fixtures and stub table drive them); a
/// file of their own only because that one is already at SwiftLint's length
/// gate.
extension PilgrimagePackageManagerTests {

    /// A response with no `Content-Length` leaves `expectedContentLength` at
    /// -1, which passes the guard before the drain — so only the cap counted
    /// while streaming can refuse this one. `route.json` rather than a stage
    /// because its ceiling is a quarter of the size to drain byte by byte.
    func testAFileThatNeverDeclaresItsLengthIsRefusedByTheCapCountedWhileStreaming() async throws {
        let huge = Data(repeating: 0x20, count: PilgrimageWayImporter.maxRouteBytes + 1)
        StubURLProtocol.stub(url: try url("route.json"), body: huge,
                             headers: ["Content-Type": "application/json"])
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertNil(manager.installed())
        XCTAssertTrue(wayStore.list().isEmpty, "nothing of a refused package is kept")
    }

    /// A tag the index named that the CDN does not carry answers 404. The body
    /// is a valid route file, so only the status check can refuse it.
    func testAStageServedAsNotFoundIsAnUnfinishedDownload() async throws {
        StubURLProtocol.stub(url: try url("stage-01.json"), status: 404,
                             body: try PilgrimageFixtures.data("stage-01.json"))
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertNil(manager.installed())
        XCTAssertTrue(wayStore.list().isEmpty, "nothing reaches the store until every file has landed")
        XCTAssertEqual(manager.phase, .failed(.incomplete))
    }
}
