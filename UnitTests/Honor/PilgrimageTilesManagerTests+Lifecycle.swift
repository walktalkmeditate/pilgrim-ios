// UnitTests/Honor/PilgrimageTilesManagerTests+Lifecycle.swift
import XCTest
@testable import Pilgrim

extension PilgrimageTilesManagerTests {

    func testRemoveClearsExactlyThePrefixAndLeavesPacks() {
        loader.seedStylePacks()
        for way in stages(3) { loader.seed(id: way.id, corridorHash: "h") }
        loader.seed(id: "pilgrimage:kumano-kodo-nakahechi:0", corridorHash: "h")
        manager.remove(routeId: "camino-frances")
        XCTAssertEqual(Set(loader.removedIds), Set(stages(3).map(\.id)))
        XCTAssertNotNil(loader.regions().first { $0.id == "pilgrimage:kumano-kodo-nakahechi:0" })
        XCTAssertEqual(loader.stylePacks, Set(StylePackRequest.allCases))
    }

    func testRemoveCancelsAnInFlightSave() async {
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(2)) }
        await Task.yield()
        manager.remove(routeId: "camino-frances")
        _ = try? await task.value
        XCTAssertEqual(manager.phase, .idle)
    }

    func testRetiredIndicesAreRemovedAndNothingIsDownloaded() {
        for way in stages(5) { loader.seed(id: way.id, corridorHash: "h") }
        manager.removeRegions(routeId: "camino-frances", atOrAbove: 3)
        XCTAssertEqual(Set(loader.removedIds), ["pilgrimage:camino-frances:3", "pilgrimage:camino-frances:4"])
        XCTAssertTrue(loader.regionRequests.isEmpty)
        XCTAssertTrue(loader.packRequests.isEmpty)
    }

    func testReconcileRemovesForeignAndOutOfRangeRegionsAndIsIdempotent() {
        for way in stages(3) { loader.seed(id: way.id, corridorHash: "h") }
        loader.seed(id: "pilgrimage:camino-frances:7", corridorHash: "h")
        loader.seed(id: "pilgrimage:kumano-kodo-nakahechi:0", corridorHash: "h")
        manager.reconcile(installed: (routeId: "camino-frances", stageCount: 3))
        XCTAssertEqual(Set(loader.removedIds), ["pilgrimage:camino-frances:7", "pilgrimage:kumano-kodo-nakahechi:0"])
        let before = loader.removedIds.count
        manager.reconcile(installed: (routeId: "camino-frances", stageCount: 3))
        XCTAssertEqual(loader.removedIds.count, before, "a second run removes nothing")
    }

    /// The launch reconcile runs against a loader whose cache is still empty:
    /// the store answers asynchronously and the first sweep sees nothing. It
    /// has to run again when the answer lands — and only then.
    func testReconcileSweepsOnceTheStoreAnswers() {
        loader.seed(id: "pilgrimage:camino-frances:7", corridorHash: "h")
        loader.seed(id: "pilgrimage:kumano-kodo-nakahechi:0", corridorHash: "h")
        loader.withholdsRegions = true

        manager.reconcile(installed: (routeId: "camino-frances", stageCount: 3))
        XCTAssertTrue(loader.removedIds.isEmpty, "the store has not answered yet")

        loader.releaseRegions()
        XCTAssertEqual(Set(loader.removedIds), ["pilgrimage:camino-frances:7", "pilgrimage:kumano-kodo-nakahechi:0"])

        let before = loader.removedIds.count
        loader.releaseRegions()
        XCTAssertEqual(loader.removedIds.count, before, "the held request ran once, not on every later change")
    }

    /// On a phone that has saved maps the style-pack answer comes back a
    /// round trip ahead of the regions. If it released the held request, the
    /// sweep would run against a cache that is still empty and the regions
    /// answer would find nothing left to do.
    func testAPacksOnlyChangeDoesNotConsumeTheHeldReconcile() {
        loader.seed(id: "pilgrimage:camino-frances:7", corridorHash: "h")
        loader.seed(id: "pilgrimage:kumano-kodo-nakahechi:0", corridorHash: "h")
        loader.withholdsRegions = true

        manager.reconcile(installed: (routeId: "camino-frances", stageCount: 3))
        loader.firePacksChange()
        XCTAssertTrue(loader.removedIds.isEmpty, "the packs answer does not speak for what is on disk")

        loader.releaseRegions()
        XCTAssertEqual(Set(loader.removedIds), ["pilgrimage:camino-frances:7", "pilgrimage:kumano-kodo-nakahechi:0"])
    }

    func testReconcileWithNothingInstalledRemovesEveryRegion() {
        for way in stages(2) { loader.seed(id: way.id, corridorHash: "h") }
        manager.reconcile(installed: nil)
        XCTAssertEqual(Set(loader.removedIds), Set(stages(2).map(\.id)))
    }
}
