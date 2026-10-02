import XCTest
@testable import Pilgrim

/// What a route's install and removal leave behind, and what they must not
/// take with them. Cases of `PilgrimagePackageManagerTests` (its fixtures and
/// stub table drive them); a file of their own only because that one is
/// already at SwiftLint's length gate.
extension PilgrimagePackageManagerTests {

    /// The store's base, reached through the one path it publishes. The walk
    /// index sits beside the pilgrimage folder, not inside it.
    private var walkIndexURL: URL {
        wayStore.pilgrimageRoot.deletingLastPathComponent().appendingPathComponent("index.json")
    }

    private var markerURL: URL {
        wayStore.pilgrimageRoot.appendingPathComponent(PilgrimagePackageManager.replacingMarkerName)
    }

    // MARK: - What Remove must leave

    /// Remove promises "Walks in your journal stay". It cannot keep that
    /// promise by taking the stage Way a walk is linked to: the link goes with
    /// it, the summary reads "a way that has been removed", and the prompt
    /// falls into the shared-walk lexicon that speaks of two travelling
    /// together. The sweep's rule already knows better — a walked Way keeps
    /// its folder, its reply, and its link.
    func testARemovedRoutesWalkedStageKeepsItsLinkItsReplyAndItsStageIdentity() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        let walk = UUID()
        let stageId = WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0)
        try wayStore.link(walkUUID: walk, to: stageId, arrival: nil)
        try wayStore.setReply(wayId: stageId, originN: HonorPersistence.stageReflectionOrigin,
                              relativePath: "Recordings/reply.m4a")

        try manager.remove(routeId: "camino-frances")

        XCTAssertEqual(wayStore.wayLink(forWalk: walk)?.wayId, stageId, "the walk still names its stage")
        let way = try XCTUnwrap(wayStore.way(forWalk: walk))
        let honored = WalkDataFactory.makeWalk(
            workoutEvents: [TempWalkEvent(uuid: nil, eventType: .honorMode, timestamp: Date())])
        let summary = try XCTUnwrap(HonorSummaryModel.summaryData(
            for: honored, way: way, link: wayStore.wayLink(forWalk: walk),
            replies: wayStore.replies(for: stageId), ledger: nil))
        XCTAssertTrue(summary.isPilgrimageStage, "not the shared-walk lexicon")
        XCTAssertEqual(summary.wayTitle, way.title, "not 'a way that has been removed'")
        XCTAssertEqual(summary.replyRelativePath, "Recordings/reply.m4a")

        XCTAssertNil(wayStore.load(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 1)),
                     "the stage nobody walked goes whole")
        XCTAssertNil(manager.installed(), "what is kept never reads as installed")
    }

    /// `delete(id:)` rewrites `index.json` on every call, so a Remove used to
    /// pay one read-modify-write per stage — two hundred of them on a whole
    /// camino. The index below is written by hand with indentation the store's
    /// own encoder never produces, so a single rewrite shows as a changed byte.
    func testRemovingARouteReadsTheWalkIndexWithoutRewritingItPerStage() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        let walk = UUID()
        try wayStore.link(walkUUID: walk, to: WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0), arrival: nil)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: walkIndexURL)) as? [String: Any])
        let handWritten = try JSONSerialization.data(withJSONObject: decoded, options: [.prettyPrinted])
        try handWritten.write(to: walkIndexURL, options: .atomic)

        try manager.remove(routeId: "camino-frances")

        XCTAssertEqual(try Data(contentsOf: walkIndexURL), handWritten, "the index was read, never rewritten")
        XCTAssertNotNil(wayStore.wayLink(forWalk: walk))
    }

    // MARK: - An interrupted Replace

    /// `replace` installs the new route before it takes the old one, so a kill
    /// inside that window leaves two valid packages and nothing in either of
    /// them to say which one the pilgrim chose. Two plain downloads leave
    /// exactly that state; the marker names the route being let go.
    func testAKillBetweenAReplacesTwoHalvesIsFinishedOnTheNextRead() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try stubNorte()
        try await manager.download(entry: norte, release: "v1.7.0")
        try Data("camino-frances".utf8).write(to: markerURL, options: .atomic)

        let installed = try XCTUnwrap(manager.installed())

        XCTAssertEqual(installed.routeId, "camino-norte", "the route the pilgrim chose survives")
        XCTAssertNil(wayStore.load(id: "pilgrimage:camino-frances:0"), "the abandoned route's stages are taken")
        let abandoned = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.appendingPathComponent("route.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path),
                       "the marker is cleared once the swap it described is finished")
    }

    func testAReplaceThatFinishesLeavesNoMarkerBehind() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try stubNorte()

        try await manager.replace(with: norte, release: "v1.7.0")

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertEqual(manager.installed()?.routeId, "camino-norte")
    }

    // MARK: - Refusals while a download is in flight

    /// A Remove taken between two stages would be undone by the commit that
    /// lands after it, and the route the pilgrim let go would be back on the
    /// phone — the same refusal a second download gets.
    func testRemoveIsRefusedWhileADownloadIsInFlight() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        StubURLProtocol.stub(url: try url("route.json", release: "v1.8.0"),
                             body: try PilgrimageFixtures.data("route.json"), delay: 0.4)
        StubURLProtocol.stub(url: try url("stage-00.json", release: "v1.8.0"),
                             body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: "v1.8.0"),
                             body: try PilgrimageFixtures.data("stage-01.json"))
        let update = Task { try await manager.update(entry: entry, release: "v1.8.0") }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertThrowsError(try manager.remove(routeId: "camino-frances")) {
            XCTAssertEqual($0 as? PilgrimageError, .incomplete)
        }

        try await update.value
        XCTAssertEqual(manager.installed()?.release, "v1.8.0", "the update the Remove could not interrupt")
        XCTAssertNotNil(wayStore.load(id: "pilgrimage:camino-frances:0"))
    }

    /// Every stage is a network round trip, so a walk can begin while they are
    /// still landing. The commit would rewrite the very Way that walk is
    /// walking, so it is refused at the last moment before it writes.
    func testAWalkBegunWhileTheStagesStreamAbortsTheCommit() async throws {
        StubURLProtocol.stub(url: try url("stage-01.json"),
                             body: try PilgrimageFixtures.data("stage-01.json"), delay: 0.4)
        let manager = makeManager()
        var walkOn = false
        manager.isWalkActive = { walkOn }
        let download = Task { try await manager.download(entry: entry, release: "v1.7.0") }
        try await Task.sleep(nanoseconds: 100_000_000)
        walkOn = true

        do {
            try await download.value
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertTrue(wayStore.list().isEmpty, "nothing of the abandoned package reached the store")
        XCTAssertNil(manager.installed())
        XCTAssertEqual(manager.phase, .failed(.walkInProgress))
    }

    // MARK: - A route file this build only partly reads

    /// `installed()` reads `route.json` through the same decode as the
    /// download. A stamp-hours shape this build cannot read must not make the
    /// route vanish from the phone — the launch sweep would then find every
    /// saved map unaccounted for and take them all.
    func testAnInstalledRouteWhoseStampHoursAreMisShapedStillReadsAsInstalled() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try rewriteInstalledRouteFile(stampHours: [["opens": "08:00", "closes": "12:00"],
                                                   ["opens": "13:00", "closes": "17:00"]])

        let installed = try XCTUnwrap(manager.installed(), "still on the phone")
        XCTAssertEqual(installed.routeId, "camino-frances")
        XCTAssertEqual(installed.route.stageCount, 2)
        XCTAssertNil(installed.route.stampHours, "a shape this build cannot read states no hours")
    }

    /// The installed `route.json` with its `stampHours` replaced, byte for
    /// byte what a dataset release would have put there.
    func rewriteInstalledRouteFile(stampHours: Any) throws {
        let file = try XCTUnwrap(wayStore.pilgrimageDirectory(for: "camino-frances")).appendingPathComponent("route.json")
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: file)) as? [String: Any])
        obj["stampHours"] = stampHours
        try JSONSerialization.data(withJSONObject: obj).write(to: file, options: .atomic)
    }

    // MARK: - Stamp hours for a route installed before the stages carried them

    /// What open-pilgrimages v1.12.0 writes on every Shikoku `route.json`.
    private static let shikokuHours = ["opens": "08:00", "closes": "17:00"]

    private var stageZeroId: String { WayStore.stageWayId(routeId: "camino-frances", stageIndex: 0) }
    private var stageOneId: String { WayStore.stageWayId(routeId: "camino-frances", stageIndex: 1) }

    /// A Shikoku leg downloaded under 2.0.0: `route.json` was copied byte for
    /// byte and carries the hours, the stage Ways staged beside it do not,
    /// and Update compares releases only — so nothing would ever offer the
    /// walker the notice. The launch pass hands the hours down, and touches
    /// nothing else a walker has made of the stage.
    func testAStageInstalledWithoutItsRoutesStampHoursLearnsThemAtLaunch() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try rewriteInstalledRouteFile(stampHours: Self.shikokuHours)
        let walk = UUID()
        try wayStore.link(walkUUID: walk, to: stageZeroId, arrival: nil)
        try wayStore.setReply(wayId: stageZeroId, originN: HonorPersistence.stageReflectionOrigin,
                              relativePath: "Recordings/reply.m4a")
        let acceptedAt = wayStore.acceptedAt(id: stageZeroId)
        let before = try XCTUnwrap(wayStore.load(id: stageZeroId))
        XCTAssertNil(before.stampHours, "the state a 2.0.0 install leaves")

        manager.restampStageHours(of: try XCTUnwrap(manager.installed()))

        let hours = WayStampHours(opensMinutes: 480, closesMinutes: 1020)
        XCTAssertEqual(wayStore.load(id: stageZeroId)?.stampHours, hours)
        XCTAssertEqual(wayStore.load(id: stageOneId)?.stampHours, hours)
        let stamped = try XCTUnwrap(wayStore.load(id: stageZeroId))
        var unstamped = stamped
        unstamped.stampHours = nil
        XCTAssertEqual(unstamped, before, "nothing but the hours is rewritten")
        XCTAssertEqual(PilgrimageTilesManager.corridorHash(for: stamped), PilgrimageTilesManager.corridorHash(for: before),
                       "a saved map region still matches its stage")
        XCTAssertEqual(wayStore.acceptedAt(id: stageZeroId), acceptedAt)
        XCTAssertEqual(wayStore.replies(for: stageZeroId)[HonorPersistence.stageReflectionOrigin], "Recordings/reply.m4a")
        XCTAssertEqual(wayStore.wayLink(forWalk: walk)?.wayId, stageZeroId)
        XCTAssertEqual(manager.installed()?.release, "v1.7.0", "the package itself is left as it was")
    }

    /// Compare, then save: every launch runs the pass, and only the first
    /// after the app update has anything to write.
    func testASecondLaunchPassWritesNothing() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try rewriteInstalledRouteFile(stampHours: Self.shikokuHours)
        let saves = countingSaves(on: manager)

        manager.restampStageHours(of: try XCTUnwrap(manager.installed()))
        XCTAssertEqual(saves.count, 2, "both stages lacked them")

        manager.restampStageHours(of: try XCTUnwrap(manager.installed()))
        XCTAssertEqual(saves.count, 2, "the second pass found nothing to change")
    }

    /// Every route but Shikoku's states no hours, and the pass leaves its
    /// stages exactly as they are.
    func testARouteThatStatesNoStampHoursIsLeftAlone() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        let saves = countingSaves(on: manager)

        manager.restampStageHours(of: try XCTUnwrap(manager.installed()))

        XCTAssertEqual(saves.count, 0)
        XCTAssertNil(wayStore.load(id: stageZeroId)?.stampHours)
    }

    /// A launch pass must never take the launch down with it: a stage the
    /// disk refuses stays silent until the next launch tries again, and the
    /// rest still learn their hours.
    func testAStageThatCannotBeWrittenLeavesTheRestStamped() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try rewriteInstalledRouteFile(stampHours: Self.shikokuHours)
        let store = wayStore!
        let refused = stageZeroId
        manager.saveStage = { way in
            if way.id == refused { throw CocoaError(.fileWriteOutOfSpace) }
            try store.save(way)
        }

        manager.restampStageHours(of: try XCTUnwrap(manager.installed()))

        XCTAssertNil(wayStore.load(id: stageZeroId)?.stampHours, "left as it was")
        XCTAssertNotNil(wayStore.load(id: stageOneId)?.stampHours)
    }

    /// An Update's commit writes the same stage files from off the main
    /// actor; a pass that loaded a stage before the commit and saved it after
    /// would put the old stage back. The download stamps its own stages.
    func testThePassStandsAsideWhileADownloadIsInFlight() async throws {
        let manager = makeManager()
        try await manager.download(entry: entry, release: "v1.7.0")
        try rewriteInstalledRouteFile(stampHours: Self.shikokuHours)
        let installed = try XCTUnwrap(manager.installed())
        StubURLProtocol.stub(url: try url("route.json", release: "v1.8.0"),
                             body: try PilgrimageFixtures.data("route.json"), delay: 0.4)
        StubURLProtocol.stub(url: try url("stage-00.json", release: "v1.8.0"),
                             body: try PilgrimageFixtures.data("stage-00.json"))
        StubURLProtocol.stub(url: try url("stage-01.json", release: "v1.8.0"),
                             body: try PilgrimageFixtures.data("stage-01.json"))
        let saves = countingSaves(on: manager)
        let update = Task { try await manager.update(entry: entry, release: "v1.8.0") }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard case .downloading = manager.phase else {
            XCTFail("the Update finished before the pass ran, so this proves nothing: lengthen route.json's stub delay")
            try await update.value
            return
        }

        manager.restampStageHours(of: installed)

        XCTAssertEqual(saves.count, 0, "nothing written while the download holds the stages")
        try await update.value
    }

    /// Every write the manager makes to a stage Way, counted on the way to
    /// this test's own store.
    private final class SaveCount { var count = 0 }

    private func countingSaves(on manager: PilgrimagePackageManager) -> SaveCount {
        let saves = SaveCount()
        let store = wayStore!
        manager.saveStage = { way in
            saves.count += 1
            try store.save(way)
        }
        return saves
    }

    // MARK: - A stage that disagrees with its route file

    /// `route.json` and the stage files come down separately. A stage that
    /// counts a different number of stages than the route it belongs to would
    /// have the morning card reading "stage 1 of 3" against a screen counting
    /// two.
    func testAStageThatCountsADifferentNumberOfStagesThanItsRouteIsRefused() async throws {
        StubURLProtocol.stub(url: try url("stage-00.json"), body: try patchedStageZero(count: 3))
        let manager = makeManager()

        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
        XCTAssertNil(manager.installed())
        XCTAssertTrue(wayStore.list().isEmpty)
    }

    /// The route file names every stage, and the ledger reconciles by that
    /// name. A stage carrying a name the route never used would be dropped
    /// from the ledger the first time a package updated.
    func testAStageCarryingANameItsRouteFileNeverUsedIsRefused() async throws {
        StubURLProtocol.stub(url: try url("stage-00.json"), body: try patchedStageZero(name: "Somewhere else entirely"))
        let manager = makeManager()

        do {
            try await manager.download(entry: entry, release: "v1.7.0")
            XCTFail("expected notWalkable")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .notWalkable)
        }
        XCTAssertNil(manager.installed())
        XCTAssertTrue(wayStore.list().isEmpty)
    }

    /// The fixture's first stage with one field of its stage block rewritten,
    /// everything else — including what the importer validates on its own —
    /// left exactly as it was.
    private func patchedStageZero(count: Int? = nil, name: String? = nil) throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("stage-00.json")) as? [String: Any])
        var stage = try XCTUnwrap(obj["stage"] as? [String: Any])
        if let count { stage["count"] = count }
        if let name { stage["name"] = name }
        obj["stage"] = stage
        return try JSONSerialization.data(withJSONObject: obj)
    }
}
