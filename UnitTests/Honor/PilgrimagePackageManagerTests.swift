import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimagePackageManagerTests: XCTestCase {

    private var dir: URL!
    /// Not private: the streaming cases drive it from their own file.
    var wayStore: WayStore!
    private var ledgers: PilgrimageLedgerStore!

    let entry = PilgrimageCatalogEntry(
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

    func url(_ file: String, release: String = "v1.7.0") throws -> URL {
        try XCTUnwrap(PilgrimageCatalogService.packageURL(release: release, routeId: "camino-frances", file: file))
    }

    private func stubWholePackage(release: String = "v1.7.0") throws {
        StubURLProtocol.stub(url: try url("route.json", release: release), body: try PilgrimageFixtures.data("route.json"))
        StubURLProtocol.stub(url: try url("stage-00.json", release: release), body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: release), body: try PilgrimageFixtures.data("stage-01.json"))
    }

    func makeManager() -> PilgrimagePackageManager {
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
        XCTAssertTrue(seen.contains(.downloading(done: 0, total: 3)) && seen.contains(.downloading(done: 1, total: 3)), "busy before route.json's round trip, then again once it lands")
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

    /// The declared-length path — the stub writes a truthful `Content-Length`. The running cap is proved in the streaming file.
    func testAStageFileThatDeclaresMoreThanTheCapIsRefusedBeforeItIsBuffered() async throws {
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

    // MARK: - Update rollback

    /// A second `download` for a route already installed overwrites its
    /// stages in place. If the commit fails partway, a rollback scoped to
    /// only the indices this attempt itself wrote would leave the untouched
    /// stage from the *previous* install sitting on disk with no
    /// `route.json` to name it.
    func testAFailedUpdateRollsBackTheWholePreviousInstallEvenAtTheSameStageCount() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        XCTAssertNotNil(manager.installed())

        let store = wayStore!
        var saves = 0
        manager.saveStage = { way in
            saves += 1
            if saves == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try store.save(way)
        }
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected diskFull")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .diskFull)
        }
        XCTAssertTrue(wayStore.list().isEmpty, "no stage from the failed update or the prior install survives")
        XCTAssertNil(manager.installed())
        let packageDir = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("route.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("release.txt").path))
    }

    /// The previous install can be larger than the one replacing it. The
    /// failed commit below only ever writes indices 0 and 1 — index 2 is
    /// never touched by this attempt at all — so the rollback has to reach
    /// past what this commit wrote to find it.
    func testAFailedUpdateRollsBackStagesLeftoverFromALargerPreviousInstall() async throws {
        let entry3 = PilgrimageCatalogEntry(
            id: "camino-frances", name: entry.name, names: [:], country: "ES",
            region: "Europe", distanceKm: 46.1, tradition: "christian", stageCount: 3, bytes: 300_000)
        StubURLProtocol.stub(url: try url("route.json"), body: try threeStageRouteData())
        StubURLProtocol.stub(url: try url("stage-02.json"), body: try stage02Data())
        let manager = makeManager()
        try await manager.download(entry: entry3, release: "v1.7.0")
        XCTAssertEqual(try XCTUnwrap(manager.installed()).route.stages.count, 3)

        try stubWholePackage()
        let store = wayStore!
        var saves = 0
        manager.saveStage = { way in
            saves += 1
            if saves == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try store.save(way)
        }
        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected diskFull")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .diskFull)
        }
        XCTAssertTrue(wayStore.list().isEmpty, "the leftover third stage from the larger previous install is gone too")
        XCTAssertNil(manager.installed())
        let packageDir = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("route.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.appendingPathComponent("release.txt").path))
    }

    // MARK: - Reentrancy

    /// `download` suspends at every network await, so nothing stops a second
    /// call from interleaving with one already in flight — whose rollback
    /// could then tear down the first's clean install. The route.json fetch
    /// is held open so the first call is still mid-flight when the second
    /// one is made.
    func testASecondDownloadIsRefusedWhileOneIsInFlight() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub(url: try url("route.json"), body: try PilgrimageFixtures.data("route.json"), delay: 0.3)
        StubURLProtocol.stub(url: try url("stage-00.json"), body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json"), body: try PilgrimageFixtures.data("stage-01.json"))
        let manager = makeManager()
        let first = Task { try await manager.download(entry: entry, release: "v1.7.0") }
        try await Task.sleep(nanoseconds: 50_000_000)

        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }

        try await first.value
        XCTAssertEqual(wayStore.load(id: "pilgrimage:camino-frances:0")?.stage?.theme, "Initiation")
        XCTAssertEqual(wayStore.load(id: "pilgrimage:camino-frances:1")?.stage?.theme, "Descent")
        XCTAssertNotNil(manager.installed())
    }

    // MARK: - Fixture mutation

    /// A three-stage variant of the fixture route, built by JSON mutation
    /// rather than a fourth checked-in fixture: only this one test needs a
    /// previous install larger than the package replacing it.
    private func threeStageRouteData() throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("route.json")) as? [String: Any])
        var stages = try XCTUnwrap(obj["stages"] as? [[String: Any]])
        stages.append([
            "index": 2, "name": "Zubiri to Pamplona", "distanceKm": 20.4, "gainMeters": 128.0,
            "hours": ["min": 5.0, "max": 6.0], "difficulty": "easy"
        ])
        obj["stageCount"] = 3
        obj["stages"] = stages
        return try JSONSerialization.data(withJSONObject: obj)
    }

    /// `stage-01.json` reshaped into the third stage of `threeStageRouteData()`.
    private func stage02Data() throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("stage-01.json")) as? [String: Any])
        var stage = try XCTUnwrap(obj["stage"] as? [String: Any])
        obj["id"] = "pilgrimage:camino-frances:2"
        stage["index"] = 2
        stage["count"] = 3
        obj["stage"] = stage
        return try JSONSerialization.data(withJSONObject: obj)
    }

    /// A one-stage variant of the fixture route: stage 0 kept verbatim (the identity a ledger reconciliation recognizes), stage 1 simply gone.
    private func oneStageRouteData() throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("route.json")) as? [String: Any])
        var stages = try XCTUnwrap(obj["stages"] as? [[String: Any]])
        stages.removeLast()
        obj["stageCount"] = 1
        obj["stages"] = stages
        return try JSONSerialization.data(withJSONObject: obj)
    }

    private var entryWithOneStage: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-frances", name: entry.name, names: [:], country: "ES",
                               region: "Europe", distanceKm: 24.2, tradition: "christian", stageCount: 1, bytes: 100_000)
    }

    private func stubOneStagePackage(release: String) throws {
        StubURLProtocol.stub(url: try url("route.json", release: release), body: try oneStageRouteData())
        StubURLProtocol.stub(url: try url("stage-00.json", release: release), body: try PilgrimageFixtures.data("stage-00.json"))
    }

    /// Both stages walked, so a reconciliation test can show one entry surviving and the other dropped.
    private func seedTwoStageLedger() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2, outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9, outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)
    }
}

extension PilgrimagePackageManagerTests {

    private var norte: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-norte", name: "Camino del Norte", names: [:], country: "ES",
                               region: "Europe", distanceKm: 46.1, tradition: "christian",
                               stageCount: 2, bytes: 214_000)
    }

    /// The same two fixture stages, re-slugged as a second route.
    private func stubNorte(release: String = "v1.7.0") throws {
        func reslugged(_ name: String) throws -> Data {
            let text = String(data: try PilgrimageFixtures.data(name), encoding: .utf8)!
                .replacingOccurrences(of: "camino-frances", with: "camino-norte")
            return Data(text.utf8)
        }
        for (file, fixture) in [("route.json", "route.json"),
                                ("stage-00.json", "stage-00.json"),
                                ("stage-01.json", "stage-01.json")] {
            let url = try XCTUnwrap(PilgrimageCatalogService.packageURL(release: release, routeId: "camino-norte", file: file))
            StubURLProtocol.stub(url: url, body: try reslugged(fixture))
        }
    }

    func testReplaceOnlyRemovesTheFirstRouteOnceTheSecondIsComplete() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)

        try stubNorte()
        try await manager.replace(with: norte, release: "v1.7.0")

        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"), "the first route's stages left")
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"))
        XCTAssertNotNil(wayStore.load(id: "pilgrimage:camino-norte:0"))
        XCTAssertEqual(manager.installed()?.routeId, "camino-norte")
        XCTAssertEqual(ledgers.load(routeId: "camino-frances")?.completedCount, 1,
                       "what you walked of it is remembered if it comes back")
        let previousDir = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: previousDir.appendingPathComponent("route.json").path), "the old route's package is gone, not just unreachable through installed()")
    }

    /// Replacing the route you already hold needs Update's shrink tail-sweep and ledger reconciliation, not a bare download.
    func testReplaceWithTheRouteAlreadyInstalledBehavesLikeAnUpdate() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        seedTwoStageLedger()
        try stubOneStagePackage(release: "v1.8.0")
        try await manager.replace(with: entryWithOneStage, release: "v1.8.0")

        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"), "stage 1's Way is orphaned by the shrink")
        XCTAssertNotNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertEqual(manager.installed()?.release, "v1.8.0")
        let after = try XCTUnwrap(ledgers.load(routeId: "camino-frances"))
        XCTAssertEqual(Set(after.stages.keys), ["0"], "stage 1's entry was dropped, not left stale")
        XCTAssertEqual(after.redrawNoticePending, true)
    }

    func testAFailedReplaceLeavesTheFirstRouteUntouched() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        // camino-norte is never stubbed, so every fetch fails.
        do {
            try await manager.replace(with: norte, release: "v1.7.0")
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertEqual(manager.installed()?.routeId, "camino-frances")
        XCTAssertNotNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-norte:0"))
    }

    func testUpdateReconcilesTheLedgerByStageIdentity() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        seedTwoStageLedger()

        // v1.8.0 redraws stage 1 under a new name.
        let redrawnRoute = String(data: try PilgrimageFixtures.data("route.json"), encoding: .utf8)!
            .replacingOccurrences(of: "\"name\": \"Roncesvalles to Zubiri\"", with: "\"name\": \"Roncesvalles to Larrasoaña\"")
        let redrawnStage = String(data: try PilgrimageFixtures.data("stage-01.json"), encoding: .utf8)!
            .replacingOccurrences(of: "Roncesvalles to Zubiri", with: "Roncesvalles to Larrasoaña")
        StubURLProtocol.stub(url: try url("route.json", release: "v1.8.0"), body: Data(redrawnRoute.utf8))
        StubURLProtocol.stub(url: try url("stage-00.json", release: "v1.8.0"), body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: "v1.8.0"), body: Data(redrawnStage.utf8))

        try await manager.update(entry: entry, release: "v1.8.0")

        XCTAssertEqual(manager.installed()?.release, "v1.8.0")
        let after = try XCTUnwrap(ledgers.load(routeId: "camino-frances"))
        XCTAssertEqual(Set(after.stages.keys), ["0"])
        XCTAssertEqual(after.carriedKm ?? 0, 21.9, accuracy: 0.01)
        XCTAssertEqual(after.redrawNoticePending, true)
    }

    /// A route that shrank leaves stage Ways above the new count behind, with nothing to reach them once `route.json` stops naming that index.
    func testUpdateSweepsStageWaysTheNewPackageNoLongerCovers() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")

        try stubOneStagePackage(release: "v1.8.0")
        try await manager.update(entry: entryWithOneStage, release: "v1.8.0")

        XCTAssertNil(wayStore.load(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 1)), "the tail stage above the new count is swept")
        XCTAssertNotNil(wayStore.load(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0)))
        XCTAssertEqual(manager.installed()?.route.stageCount, 1)
    }

    func testRemoveTakesTheStagesAndKeepsTheLedger() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "a", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)

        try manager.remove(routeId: "camino-frances")

        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:1"))
        XCTAssertNil(manager.installed())
        XCTAssertEqual(ledgers.load(routeId: "camino-frances")?.completedCount, 1)
    }

    func testReplaceUpdateAndRemoveAreAllRefusedMidWalk() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        manager.isWalkActive = { true }
        try stubNorte()

        do {
            try await manager.replace(with: norte, release: "v1.7.0")
            XCTFail("replace")
        } catch { XCTAssertEqual(error as? PilgrimageError, .walkInProgress) }
        do {
            try await manager.update(entry: entry, release: "v1.8.0")
            XCTFail("update")
        } catch { XCTAssertEqual(error as? PilgrimageError, .walkInProgress) }
        XCTAssertThrowsError(try manager.remove(routeId: "camino-frances")) {
            XCTAssertEqual($0 as? PilgrimageError, .walkInProgress)
        }
        XCTAssertEqual(manager.installed()?.routeId, "camino-frances", "nothing moved")
    }

    func testTheConfirmationsNameTheRouteAndTheirOwnVerb() {
        XCTAssertEqual(
            PilgrimagePackageManager.replaceConfirmation(routeName: "Camino Francés"),
            "Replace the Camino Francés? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay.")
        XCTAssertEqual(
            PilgrimagePackageManager.removeConfirmation(routeName: "Camino Francés"),
            "Remove the Camino Francés? Its stages leave your phone; what you've walked of it is remembered if it comes back. Walks in your journal stay.")
        XCTAssertFalse(PilgrimagePackageManager.removeConfirmation(routeName: "x").hasPrefix("Replace"),
                       "the Remove alert must not ask about replacing")
    }
}
