import XCTest
@testable import Pilgrim

final class ShareMediaUploadTests: XCTestCase {

    func testRequestShapeMatchesWorkerContract() {
        let req = ShareService.mediaUploadRequest(shareID: "abc123defg", kind: .audio, n: 3, contentLength: 12345)
        XCTAssertEqual(req.url?.absoluteString, "https://walk.pilgrimapp.org/api/share/abc123defg/audio/3")
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Length"), "12345")
        XCTAssertNotNil(req.value(forHTTPHeaderField: "X-Device-Token"))
    }

    func testPhotoRequestUsesJpegContentType() {
        let req = ShareService.mediaUploadRequest(shareID: "abc123defg", kind: .photos, n: 1, contentLength: 500)
        XCTAssertEqual(req.url?.absoluteString, "https://walk.pilgrimapp.org/api/share/abc123defg/photos/1")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
    }

    func testCacheFailedMedia_roundTripsThenEmptyClears() {
        let walkID = UUID()
        let failures: [(kind: ShareService.MediaKind, n: Int)] = [(.photos, 2), (.audio, 1)]

        ShareService.cacheFailedMedia(failures, walkID: walkID)
        let reloaded = ShareService.failedMedia(for: walkID)
        XCTAssertEqual(reloaded.map { "\($0.kind.rawValue):\($0.n)" }, ["photos:2", "audio:1"])

        ShareService.cacheFailedMedia([], walkID: walkID)
        XCTAssertTrue(ShareService.failedMedia(for: walkID).isEmpty)
    }
}
