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
        XCTAssertEqual(req.timeoutInterval, 30, "an idle timeout, not a whole-upload one — it resets on bytes moving")
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

        // Simulates the per-item prune `completeShare`/`retryFailedMedia` perform via
        // `uploadAllMedia`/`uploadSpecific`'s `onItemSuccess`: a completed (kind, n) removed
        // from the cached record with the same read-modify-write `cacheFailedMedia` round trip.
        let afterOnePruned = ShareService.failedMedia(for: walkID).filter { !($0.kind == "audio" && $0.n == 1) }
        ShareService.cacheFailedMedia(afterOnePruned, walkID: walkID)
        XCTAssertEqual(ShareService.failedMedia(for: walkID), [failures[0]], "pruning the completed item must remove exactly it, leaving the other cached failure untouched")

        ShareService.cacheFailedMedia([], walkID: walkID)
        XCTAssertTrue(ShareService.failedMedia(for: walkID).isEmpty)
    }

    // MARK: - Round 2 review: honest background budget

    override func tearDown() {
        ShareService.backgroundStateProvider = { (UIApplication.shared.applicationState == .background, UIApplication.shared.backgroundTimeRemaining) }
        super.tearDown()
    }

    @MainActor
    func testBackgroundStateProviderDefaultReflectsRealApplicationState() {
        let state = ShareService.backgroundStateProvider()
        XCTAssertFalse(state.isBackground, "the test host runs foreground — the default provider must read UIApplication directly, not report background")
    }

    func testUploadAllMediaSkipsNetworkWhenBackgroundExhausted() async {
        ShareService.backgroundStateProvider = { (true, 2) } // background, well under the 10s threshold

        let audioFiles = [URL(fileURLWithPath: "/tmp/pilgrim-share-media-upload-tests-nonexistent.m4a")]
        let photos = [Data([0xAA]), Data([0xBB])]
        var lastProgress: ShareService.MediaProgress?

        let failures = await ShareService.uploadAllMedia(shareID: "test-share-id", audioFiles: audioFiles, photos: photos) { progress in
            lastProgress = progress
        }

        XCTAssertEqual(failures.count, audioFiles.count + photos.count, "background-exhausted from the very first item of each loop must fail everything without attempting a PUT — the nonexistent audio fileURL never gets read")
        XCTAssertEqual(lastProgress, ShareService.MediaProgress(completed: audioFiles.count + photos.count, total: audioFiles.count + photos.count), "the per-loop skip accounting must still land exactly on (total, total)")
    }
}
