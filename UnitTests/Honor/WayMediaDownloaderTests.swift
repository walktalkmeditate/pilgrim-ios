import XCTest
@testable import Pilgrim

final class WayMediaDownloaderTests: XCTestCase {

    func testMediaFilesListsEveryFileOnce() {
        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: nil, kind: .voice(endFrac: 0.2, duration: 1, kind: .spoken, media: .file("audio/1.m4a"))),
            WayMoment(id: "voice-2", frac: 0.3, at: nil, kind: .voice(endFrac: 0.4, duration: 1, kind: .ambient, media: .file("audio/2.m4a"))),
            WayMoment(id: "photo-1", frac: 0.5, at: nil, kind: .photo(media: .file("photos/1.jpg"))),
            WayMoment(id: "rest-1", frac: 0.6, at: nil, kind: .rest(minutes: 3))
        ]
        let way = Way(id: "share:a", source: .share(id: "a", pageURL: URL(string: "https://walk.pilgrimapp.org/a")!), title: "t",
                      departedAt: Date(), tzIdentifier: nil, expires: nil, route: [], totalDistanceMeters: 0,
                      theirActiveSeconds: 0, moments: moments, weather: nil)
        XCTAssertEqual(WayMediaDownloader.mediaFiles(for: way), ["audio/1.m4a", "audio/2.m4a", "photos/1.jpg"])
        XCTAssertEqual(WayMediaDownloader.remoteURL(shareId: "a", relative: "audio/1.m4a").absoluteString,
                       "https://walk.pilgrimapp.org/a/audio/1.m4a")
        XCTAssertEqual(WayMediaDownloader.byteCap(for: "audio/1.m4a"), 15 * 1024 * 1024)
        XCTAssertEqual(WayMediaDownloader.byteCap(for: "photos/1.jpg"), 2 * 1024 * 1024)
    }

    /// No network involved: every file the downloader would fetch is already
    /// on disk, so `download` must resolve to full progress without touching
    /// `active` or resuming a single task.
    @MainActor
    func testDownloadWithEverythingAlreadyOnDiskCompletesImmediately() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = WayStore(baseDirectory: dir)
        let downloader = WayMediaDownloader(store: store, sessionIdentifier: "test-\(UUID())")

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
    }
}
