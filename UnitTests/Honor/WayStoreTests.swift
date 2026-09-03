import XCTest
@testable import Pilgrim

final class WayStoreTests: XCTestCase {

    private var dir: URL!
    private var store: WayStore!
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private var clock = Date(timeIntervalSince1970: 2_000_000)

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        clock = Date(timeIntervalSince1970: 2_000_000)
        store = WayStore(baseDirectory: dir, now: { [unowned self] in self.clock })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func way(id: String, expires: Date?) -> Way {
        Way(id: id, source: .share(id: "abc", pageURL: URL(string: "https://walk.pilgrimapp.org/abc")!),
            title: id, departedAt: now, tzIdentifier: nil, expires: expires,
            route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0), WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
            totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
    }

    func testSaveLoadListAndBackupExclusion() throws {
        try store.save(way(id: "share:aaaaaaaaaa", expires: nil))
        XCTAssertEqual(store.load(id: "share:aaaaaaaaaa")?.title, "share:aaaaaaaaaa")
        XCTAssertEqual(store.list().map(\.id), ["share:aaaaaaaaaa"])
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testLinkAndRepliesSurviveMediaDeletion() throws {
        try store.save(way(id: "share:aaaaaaaaaa", expires: nil))
        let walk = UUID()
        try store.link(walkUUID: walk, to: "share:aaaaaaaaaa", arrival: (theirSeconds: 600, yourSeconds: 540))
        try store.setReply(wayId: "share:aaaaaaaaaa", originN: 3, relativePath: "Recordings/x/y.m4a")
        let media = store.mediaURL(for: "share:aaaaaaaaaa", relative: "audio/1.m4a")
        try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1024).write(to: media)
        XCTAssertGreaterThanOrEqual(store.diskUsage(id: "share:aaaaaaaaaa"), 1024)
        XCTAssertTrue(store.hasMedia(id: "share:aaaaaaaaaa"))
        store.deleteMedia(id: "share:aaaaaaaaaa")
        XCTAssertFalse(store.hasMedia(id: "share:aaaaaaaaaa"))
        XCTAssertEqual(store.wayId(forWalk: walk), "share:aaaaaaaaaa")
        XCTAssertEqual(store.wayLink(forWalk: walk), WayLink(wayId: "share:aaaaaaaaaa", theirSeconds: 600, yourSeconds: 540))
        XCTAssertEqual(store.replies(for: "share:aaaaaaaaaa"), [3: "Recordings/x/y.m4a"])
        XCTAssertEqual(store.way(forWalk: walk)?.id, "share:aaaaaaaaaa")
    }

    func testSweepFollowsTheThreeRowTable() throws {
        let past = now.addingTimeInterval(-1), future = now.addingTimeInterval(86_400)
        let ownId = "walk:\(UUID().uuidString)"
        try store.save(way(id: "share:unwalkedXX", expires: past))
        try store.save(way(id: "share:walkedXXXX", expires: past))
        try store.save(way(id: "share:liveliveli", expires: future))
        try store.save(Way(id: ownId, source: .ownWalk(UUID()), title: "own", departedAt: now, tzIdentifier: nil,
                           expires: nil, route: [], totalDistanceMeters: 0, theirActiveSeconds: 0, moments: [], weather: nil))
        try store.link(walkUUID: UUID(), to: "share:walkedXXXX", arrival: nil)
        for id in ["share:unwalkedXX", "share:walkedXXXX", "share:liveliveli"] {
            let media = store.mediaURL(for: id, relative: "audio/1.m4a")
            try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: media)
        }
        let swept = store.sweepExpired(now: now)
        XCTAssertEqual(Set(swept), ["share:unwalkedXX", "share:walkedXXXX"])
        XCTAssertNil(store.load(id: "share:unwalkedXX"), "whole folder gone")
        XCTAssertNotNil(store.load(id: "share:walkedXXXX"), "way.json kept")
        XCTAssertFalse(store.hasMedia(id: "share:walkedXXXX"), "media gone")
        XCTAssertTrue(store.hasMedia(id: "share:liveliveli"))
        XCTAssertNotNil(store.load(id: ownId))
    }

    func testStrayFolderNamesAreIgnoredAndBadIdsRefused() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("..%2Fescape"), withIntermediateDirectories: true)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertThrowsError(try store.save(way(id: "share:../x", expires: nil)))
        XCTAssertFalse(WayStore.isValidId("index.json"))
        XCTAssertTrue(WayStore.isValidId("walk:\(UUID().uuidString)"))
    }

    func testReadPathsGuardInvalidIdsWithoutTrapping() throws {
        XCTAssertNil(store.load(id: "index.json"))
        XCTAssertEqual(store.replies(for: "../x"), [:])
        XCTAssertThrowsError(try store.link(walkUUID: UUID(), to: "../x", arrival: nil))
        XCTAssertThrowsError(try store.setReply(wayId: "../x", originN: 1, relativePath: "a"))
    }

    func testDeleteRemovesEverythingAndTheIndexLink() throws {
        try store.save(way(id: "share:aaaaaaaaaa", expires: nil))
        let walk = UUID()
        try store.link(walkUUID: walk, to: "share:aaaaaaaaaa", arrival: nil)
        store.delete(id: "share:aaaaaaaaaa")
        XCTAssertNil(store.load(id: "share:aaaaaaaaaa"))
        XCTAssertNil(store.wayId(forWalk: walk))
        XCTAssertEqual(store.totalDiskUsage(), 0)
    }

    func testListReturnsNewestAcceptedFirst() throws {
        try store.save(way(id: "share:firstfirst", expires: nil))
        clock = clock.addingTimeInterval(60)
        try store.save(way(id: "share:secondsecd", expires: nil))
        XCTAssertEqual(store.list().map(\.id), ["share:secondsecd", "share:firstfirst"])
    }

    func testResavingAWayKeepsItsAcceptedAt() throws {
        try store.save(way(id: "share:aaaaaaaaaa", expires: nil))
        let firstAcceptedAt = store.acceptedAt(id: "share:aaaaaaaaaa")
        clock = clock.addingTimeInterval(60)
        let updatedWay = Way(id: "share:aaaaaaaaaa", source: .share(id: "abc", pageURL: URL(string: "https://walk.pilgrimapp.org/abc")!),
            title: "updated", departedAt: now, tzIdentifier: nil, expires: nil,
            route: [WayPoint(lat: 0, lon: 0, alt: nil, t: 0), WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)],
            totalDistanceMeters: 111, theirActiveSeconds: 60, moments: [], weather: nil)
        try store.save(updatedWay)
        let secondAcceptedAt = store.acceptedAt(id: "share:aaaaaaaaaa")
        XCTAssertEqual(firstAcceptedAt, secondAcceptedAt)
        XCTAssertEqual(firstAcceptedAt, Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(store.load(id: "share:aaaaaaaaaa")?.title, "updated")
    }
}
