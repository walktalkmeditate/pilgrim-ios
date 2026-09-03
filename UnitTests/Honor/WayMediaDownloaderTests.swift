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

    /// Never the live host: `download` resumes real background tasks, and a
    /// spec must not reach out to walk.pilgrimapp.org to exercise its
    /// bookkeeping.
    nonisolated private static let deadHost = URL(string: "https://127.0.0.1:9/")!

    private func makeDownloader(store: WayStore, baseURL: URL = WayMediaDownloaderTests.deadHost) -> WayMediaDownloader {
        let downloader = WayMediaDownloader(store: store, sessionIdentifier: "test-\(UUID())", baseURL: baseURL)
        downloaders.append(downloader)
        return downloader
    }

    private func makeStore() -> WayStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return WayStore(baseDirectory: dir)
    }

    private func way(id: String, shareId: String, moments: [WayMoment]) -> Way {
        Way(id: id,
            source: .share(id: shareId, pageURL: URL(string: "https://walk.pilgrimapp.org/\(shareId)")!), title: "t",
            departedAt: Date(), tzIdentifier: nil, expires: nil, route: [], totalDistanceMeters: 0,
            theirActiveSeconds: 0, moments: moments, weather: nil)
    }

    private func voiceMoment(_ index: Int) -> WayMoment {
        WayMoment(id: "voice-\(index)", frac: 0.1, at: nil,
                  kind: .voice(endFrac: 0.2, duration: 1, kind: .spoken, media: .file("audio/\(index).m4a")))
    }

    private func photoMoment(_ index: Int) -> WayMoment {
        WayMoment(id: "photo-\(index)", frac: 0.5, at: nil, kind: .photo(media: .file("photos/\(index).jpg")))
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

    func testEntryFromURLRejectsTrailingNewline() {
        let url = URL(string: "https://walk.pilgrimapp.org/Qoi4YmPHLN%0A/audio/1.m4a")!
        XCTAssertNil(WayMediaDownloader.entry(from: url), "a trailing newline must not slip past the id shape")
    }

    // MARK: - Delivery gating (B1, B4)

    func testDeliveryForADeletedWayNeitherLandsNorRecreatesTheFolder() throws {
        let store = makeStore()
        let downloader = makeDownloader(store: store)
        let way = way(id: "share:cccccccccc", shareId: "cccccccccc", moments: [voiceMoment(1)])
        try store.save(way)

        downloader._test_registerTask(id: 7, wayId: way.id, relative: "audio/1.m4a")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        try Data([1, 2, 3]).write(to: temp)
        addTeardownBlock { try? FileManager.default.removeItem(at: temp) }

        // The walker deletes the Way while the transfer is still in flight.
        store.delete(id: way.id)

        downloader.deliver(taskId: 7, requestURL: nil, status: 200, size: 3, location: temp)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: "audio/1.m4a").path),
                       "a delivery for a deleted Way must not recreate its folder")
        XCTAssertFalse(downloader._test_hasTask(id: 7), "the bookkeeping for the dead transfer is dropped")
        XCTAssertNil(downloader.failures[way.id], "no state may be recorded against a Way that no longer exists")
        XCTAssertNil(downloader.progress[way.id])
    }

    func testDeliveryForALiveWayLands() throws {
        let store = makeStore()
        let downloader = makeDownloader(store: store)
        let way = way(id: "share:dddddddddd", shareId: "dddddddddd", moments: [voiceMoment(1)])
        try store.save(way)
        downloader._test_registerTask(id: 8, wayId: way.id, relative: "audio/1.m4a")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        try Data([1, 2, 3]).write(to: temp)
        addTeardownBlock { try? FileManager.default.removeItem(at: temp) }

        downloader.deliver(taskId: 8, requestURL: nil, status: 200, size: 3, location: temp)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: "audio/1.m4a").path),
                      "a live Way's file still lands — the guard must gate deletion, not delivery itself")
    }

    /// B4: a relaunch-derived target carries no remembered cap, so the cap its
    /// folder implies has to stand in — never "uncapped".
    func testRelaunchDeliveryIsStillCapped() throws {
        let store = makeStore()
        let downloader = makeDownloader(store: store)
        let way = way(id: "share:aaaaaaaaaa", shareId: "aaaaaaaaaa", moments: [photoMoment(1)])
        try store.save(way)

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        try Data([1]).write(to: temp)
        addTeardownBlock { try? FileManager.default.removeItem(at: temp) }

        let url = WayMediaDownloader.remoteURL(shareId: "aaaaaaaaaa", relative: "photos/1.jpg")
        downloader.deliver(taskId: 9, requestURL: url,
                           status: 200, size: WayMediaDownloader.byteCap(for: "photos/1.jpg") + 1, location: temp)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.mediaURL(for: way.id, relative: "photos/1.jpg").path),
                       "an oversized relaunch redelivery must be refused, not written")
    }

    // MARK: - Aggregate ceilings (B9)

    func testDownloadRefusesFilesBeyondThePerKindCeilings() throws {
        let store = makeStore()
        let downloader = makeDownloader(store: store)
        let extraAudio = WayMediaDownloader.maxAudioFilesPerWay + 2
        let extraPhotos = WayMediaDownloader.maxPhotoFilesPerWay + 3
        let moments = (1...extraAudio).map(voiceMoment) + (1...extraPhotos).map(photoMoment)
        let way = way(id: "share:eeeeeeeeee", shareId: "eeeeeeeeee", moments: moments)
        try store.save(way)

        downloader.download(way)
        addTeardownBlock { [downloader] in downloader.cancel(wayId: "share:eeeeeeeeee") }

        let refused = downloader.failures[way.id] ?? []
        XCTAssertEqual(refused.count, 5, "everything past 12 audio and 20 photos is refused before it is enqueued")
        XCTAssertTrue(refused.contains("audio/\(extraAudio).m4a"))
        XCTAssertTrue(refused.contains("photos/\(extraPhotos).jpg"))
        XCTAssertFalse(refused.contains("audio/1.m4a"), "the files inside the ceiling still go")
    }

    // MARK: - Retry (B8)

    func testRetryRestartsEvenWhileTheWayIsStillActive() throws {
        let store = makeStore()
        let downloader = makeDownloader(store: store)
        let way = way(id: "share:ffffffffff", shareId: "ffffffffff", moments: [voiceMoment(1)])
        try store.save(way)

        downloader.download(way)
        XCTAssertTrue(downloader.active.contains(way.id))

        // A retry tapped while the Way is still active used to be a silent
        // no-op; it must leave the Way downloading again, not idle.
        downloader.retry(way)
        addTeardownBlock { [downloader] in downloader.cancel(wayId: "share:ffffffffff") }

        XCTAssertTrue(downloader.active.contains(way.id), "retry re-enqueues instead of bouncing off the active guard")
    }
}
