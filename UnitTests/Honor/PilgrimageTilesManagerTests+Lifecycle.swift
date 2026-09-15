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

    func testReconcileWithNothingInstalledRemovesEveryRegion() {
        for way in stages(2) { loader.seed(id: way.id, corridorHash: "h") }
        manager.reconcile(installed: nil)
        XCTAssertEqual(Set(loader.removedIds), Set(stages(2).map(\.id)))
    }
}
