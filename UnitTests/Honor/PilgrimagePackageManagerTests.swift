import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimagePackageManagerTests: XCTestCase {

    private var dir: URL!
    private var wayStore: WayStore!
    private var ledgers: PilgrimageLedgerStore!

    private let entry = PilgrimageCatalogEntry(
        id: "camino-frances", name: "Camino de Santiago (Francés)", names: [:], country: "ES",
        region: "Europe", distanceKm: 46.1, tradition: "christian", stageCount: 2, bytes: 214_000)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        wayStore = WayStore(baseDirectory: dir)
        ledgers = PilgrimageLedgerStore(store: wayStore)
        StubURLProtocol.reset()
        try stubWholePackage()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func url(_ file: String, release: String = "v1.7.0") throws -> URL {
        try XCTUnwrap(PilgrimageCatalogService.packageURL(release: release, routeId: "camino-frances", file: file))
    }

    private func stubWholePackage(release: String = "v1.7.0") throws {
        StubURLProtocol.stub(url: try url("route.json", release: release), body: try PilgrimageFixtures.data("route.json"))
        StubURLProtocol.stub(url: try url("stage-00.json", release: release), body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: release), body: try PilgrimageFixtures.data("stage-01.json"))
    }

    private func makeManager() -> PilgrimagePackageManager {
        PilgrimagePackageManager(store: wayStore, ledgers: ledgers, session: StubURLProtocol.session())
    }

    func testStageFilesAreZeroPaddedFromZero() {
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(0), "stage-00.json")
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(9), "stage-09.json")
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(32), "stage-32.json")
        XCTAssertEqual(PilgrimagePackageManager.stageFileName(120), "stage-120.json")
    }

    func testDownloadInstallsEveryStageAndRecordsTheRelease() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")

        XCTAssertEqual(wayStore.load(id: "pilgrimage:camino-frances:0")?.stage?.theme, "Initiation")
        XCTAssertEqual(wayStore.load(id: "pilgrimage:camino-frances:1")?.stage?.theme, "Descent")
        let installed = try XCTUnwrap(manager.installed())
        XCTAssertEqual(installed.routeId, "camino-frances")
        XCTAssertEqual(installed.release, "v1.7.0")
        XCTAssertEqual(installed.route.stages.count, 2)
        XCTAssertEqual(manager.phase, .idle)
    }

    func testProgressCountsTheRouteFileAndEveryStage() async throws {
        let manager = makeManager()
        var seen: [PilgrimagePackageManager.Phase] = []
        let cancellable = manager.$phase.sink { seen.append($0) }
        try await manager.download(entry: entry, release: "v1.7.0")
        cancellable.cancel()
        XCTAssertTrue(seen.contains(.downloading(done: 1, total: 3)), "route.json landed")
        XCTAssertTrue(seen.contains(.downloading(done: 3, total: 3)), "both stages landed")
        XCTAssertEqual(seen.last, .idle)
    }

    func testAStageThatFailsValidationLeavesNothingBehind() async throws {
        let broken = String(data: try PilgrimageFixtures.data("stage-01.json"), encoding: .utf8)!
            .replacingOccurrences(of: "\"frac\": 1.0", with: "\"frac\": 9.0")
        StubURLProtocol.stub(url: try url("stage-01.json"), body: Data(broken.utf8))
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"), "the first stage is rolled back too")
        XCTAssertNil(manager.installed())
        XCTAssertEqual(manager.phase, .failed(.notWalkable))
    }

    func testANetworkFailureMidwayReportsAnUnfinishedDownload() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(url: try url("route.json"), body: try PilgrimageFixtures.data("route.json"))
        StubURLProtocol.stub(url: try url("stage-00.json"), body: try PilgrimageFixtures.data("stage-00.json"))
        // stage-01 is not stubbed: the protocol answers .notConnectedToInternet.
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertEqual(manager.phase, .failed(.incomplete))
    }

    func testAnOversizedStageFileIsRefusedBeforeItIsBuffered() async throws {
        let huge = Data(repeating: 0x20, count: PilgrimageWayImporter.maxStageBytes + 1)
        StubURLProtocol.stub(url: try url("stage-00.json"), body: huge)
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
    }

    func testARouteFileThatDoesNotMatchTheCatalogEntryIsRefused() async throws {
        let mismatched = String(data: try PilgrimageFixtures.data("route.json"), encoding: .utf8)!
            .replacingOccurrences(of: "\"stageCount\": 2", with: "\"stageCount\": 5")
        StubURLProtocol.stub(url: try url("route.json"), body: Data(mismatched.utf8))
        let manager = makeManager()
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
    }

    func testDownloadIsRefusedWhileAWalkIsOn() async throws {
        let manager = makeManager()
        manager.isWalkActive = { true }
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
    }

    /// The commit loop is the one place a half-route could survive: a stage
    /// saved before the disk filled would sit in the Ways list with no
    /// `route.json` to name it and no `installed()` able to reach it.
    func testAFailedSaveMidCommitRollsBackEveryStageAlreadyWritten() async throws {
        let manager = makeManager()
        let store = wayStore!
        var saves = 0
        manager.saveStage = { way in
            saves += 1
            // The second stage is where the disk runs out.
            if saves == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try store.save(way)
        }
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected diskFull")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .diskFull)
        }
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"),
                     "the stage that did save is taken back up")
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"))
        XCTAssertTrue(wayStore.list().isEmpty, "no orphan Ways left in the list")
        XCTAssertNil(manager.installed())
        let packageDir = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("route.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("release.txt").path))
        XCTAssertEqual(manager.phase, .failed(.diskFull))
    }

    /// The index's `bytes` is a hint the dataset wrote, not a promise the CDN
    /// keeps. The ceiling has to hold against what actually lands.
    func testTheWholePackageIsBoundedByRealBytesNotTheIndexsClaim() async throws {
        let manager = makeManager()
        manager.maxPackageBytes = 1_000
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertNil(manager.installed())
        XCTAssertTrue(wayStore.list().isEmpty)
    }
}
