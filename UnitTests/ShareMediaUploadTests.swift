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
        let failures: [ShareService.FailedMediaItem] = [
            ShareService.FailedMediaItem(kind: "photos", n: 2, audioStartTs: nil, photoLocalID: "photo-abc", photoTs: 1_000),
            ShareService.FailedMediaItem(kind: "audio", n: 1, audioStartTs: 500, photoLocalID: nil, photoTs: nil)
        ]

        ShareService.cacheFailedMedia(failures, walkID: walkID)
        let reloaded = ShareService.failedMedia(for: walkID)
        XCTAssertEqual(reloaded, failures, "round-trip through JSON must preserve identity fields, not just kind/n")

        ShareService.cacheFailedMedia([], walkID: walkID)
        XCTAssertTrue(ShareService.failedMedia(for: walkID).isEmpty)
    }
}
