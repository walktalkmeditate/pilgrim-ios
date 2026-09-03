import XCTest
@testable import Pilgrim

@MainActor
final class WayMediaDownloaderTests: XCTestCase {

    private var downloaders: [WayMediaDownloader] = []

    override func tearDown() {
        for downloader in downloaders { downloader.invalidate() }
        downloaders = []
        super.tearDown()
    }

    private func makeDownloader(store: WayStore) -> WayMediaDownloader {
        let downloader = WayMediaDownloader(store: store, sessionIdentifier: "test-\(UUID())")
        downloaders.append(downloader)
        return downloader
    }

    func testMediaFilesListsEveryFileOnce() {
        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: nil, kind: .voice(endFrac: 0.2, duration: 1, kind: .spoken, media: .file("audio/1.m4a"))),
            WayMoment(id: "voice-2", frac: 0.3, at: nil, kind: .voice(endFrac: 0.4, duration: 1, kind: .ambient, media: .file("audio/2.m4a"))),
            WayMoment(id: "photo-1", frac: 0.5, at: nil, kind: .photo(media: .file("photos/1.jpg"))),
            WayMoment(id: "rest-1", frac: 0.6, at: nil, kind: .rest(minutes: 3))
        ]
        let way = Way(id: "share:aaaaaaaaaa",
                      source: .share(id: "aaaaaaaaaa", pageURL: URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa")!), title: "t",
                      departedAt: Date(), tzIdentifier: nil, expires: nil, route: [], totalDistanceMeters: 0,
                      theirActiveSeconds: 0, moments: moments, weather: nil)
        XCTAssertEqual(WayMediaDownloader.mediaFiles(for: way), ["audio/1.m4a", "audio/2.m4a", "photos/1.jpg"])
        XCTAssertEqual(WayMediaDownloader.remoteURL(shareId: "aaaaaaaaaa", relative: "audio/1.m4a").absoluteString,
                       "https://walk.pilgrimapp.org/aaaaaaaaaa/audio/1.m4a")
        XCTAssertEqual(WayMediaDownloader.byteCap(for: "audio/1.m4a"), 15 * 1024 * 1024)
        XCTAssertEqual(WayMediaDownloader.byteCap(for: "photos/1.jpg"), 2 * 1024 * 1024)
    }

    /// No network involved: every file the downloader would fetch is already
    /// on disk, so `download` must resolve to full progress without touching
    /// `active` or resuming a single task.
    func testDownloadWithEverythingAlreadyOnDiskCompletesImmediately() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        let downloader = makeDownloader(store: store)

        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: nil, kind: .voice(endFrac: 0.2, duration: 1, kind: .spoken, media: .file("audio/1.m4a"))),
            WayMoment(id: "photo-1", frac: 0.5, at: nil, kind: .photo(media: .file("photos/1.jpg")))
        ]
        let way = Way(id: "share:aaaaaaaaaa",
                      source: .share(id: "aaaaaaaaaa", pageURL: URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa")!), title: "t",
                      departedAt: Date(), tzIdentifier: nil, expires: nil, route: [], totalDistanceMeters: 0,
                      theirActiveSeconds: 0, moments: moments, weather: nil)

        for relative in WayMediaDownloader.mediaFiles(for: way) {
            let url = store.mediaURL(for: way.id, relative: relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }

        downloader.download(way)

        XCTAssertEqual(downloader.progress[way.id], 1)
        XCTAssertFalse(downloader.active.contains(way.id))
        XCTAssertNil(downloader.failures[way.id])
    }

    /// The files are missing on purpose so `download` resumes real tasks on
    /// the background session; `cancel` must still clear every per-Way entry
    /// synchronously, without waiting on those tasks to actually complete.
    func testCancelClearsEveryPerWayEntry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        let downloader = makeDownloader(store: store)

        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: nil, kind: .voice(endFrac: 0.2, duration: 1, kind: .spoken, media: .file("audio/1.m4a")))
        ]
        let way = Way(id: "share:bbbbbbbbbb",
                      source: .share(id: "bbbbbbbbbb", pageURL: URL(string: "https://walk.pilgrimapp.org/bbbbbbbbbb")!), title: "t",
                      departedAt: Date(), tzIdentifier: nil, expires: nil, route: [], totalDistanceMeters: 0,
                      theirActiveSeconds: 0, moments: moments, weather: nil)

        downloader.download(way)
        XCTAssertTrue(downloader.active.contains(way.id))

        downloader.cancel(wayId: way.id)

        XCTAssertFalse(downloader.active.contains(way.id))
        XCTAssertNil(downloader.progress[way.id])
        XCTAssertNil(downloader.failures[way.id])
    }

    func testEntryFromURLDerivesWayIdAndRelative() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/audio/1.m4a")!
        let result = WayMediaDownloader.entry(from: url)
        XCTAssertEqual(result?.wayId, "share:aaaaaaaaaa")
        XCTAssertEqual(result?.relative, "audio/1.m4a")
    }

    func testEntryFromURLRejectsForeignHost() {
        let url = URL(string: "https://evil.example.com/aaaaaaaaaa/audio/1.m4a")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }

    func testEntryFromURLRejectsBadShareId() {
        let url = URL(string: "https://walk.pilgrimapp.org/short/audio/1.m4a")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }

    func testEntryFromURLRejectsUnknownPrefix() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/video/1.mp4")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }

    func testEntryFromURLRejectsTraversalSegment() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/audio/../../etc/passwd")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }

    /// The traversal guard on `entry(from:)` is component-wise, so a
    /// percent-encoded slash keeps this as one path component that starts
    /// with "audio/" without matching the numeric-file shape the app emits.
    func testEntryFromURLRejectsPercentEncodedTraversal() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/audio%2F..%2F..%2Fx.m4a")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }

    func testEntryFromURLRejectsPercentEncodedDotDotSegment() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/audio/%2E%2E/x.m4a")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }

    func testEntryFromURLAcceptsWellFormedAudioPath() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/audio/12.m4a")!
        let result = WayMediaDownloader.entry(from: url)
        XCTAssertEqual(result?.relative, "audio/12.m4a")
    }

    func testEntryFromURLAcceptsWellFormedPhotoPath() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/photos/3.jpg")!
        let result = WayMediaDownloader.entry(from: url)
        XCTAssertEqual(result?.relative, "photos/3.jpg")
    }

    /// The shape match is per-folder: an audio file never carries a `.jpg`
    /// extension, even though both are otherwise well-formed.
    func testEntryFromURLRejectsMismatchedExtension() {
        let url = URL(string: "https://walk.pilgrimapp.org/aaaaaaaaaa/audio/12.jpg")!
        XCTAssertNil(WayMediaDownloader.entry(from: url))
    }
}
