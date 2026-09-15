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
        await untilPending()
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

    /// The launch reconcile is asked while the store is still answering, so
    /// it sweeps nothing until the answer lands — and then exactly once.
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
        XCTAssertEqual(loader.removedIds.count, before, "the sweep ran on its answer, not on every later change")
    }

    /// On a phone that has saved maps the style-pack answer comes back a
    /// round trip ahead of the regions. It says nothing about what is on
    /// disk, so it must not stand in for the answer the sweep is waiting on.
    func testAPacksOnlyChangeDoesNotRunThePendingSweep() {
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

    /// An empty store answers "no regions", which equals the empty cache and
    /// so signals no change at all. A sweep waiting for a change would still
    /// be waiting when a save wrote its first region — and a launch that
    /// found nothing installed sweeps everything it is handed.
    func testAReconcileFromAnEmptyLaunchNeverSweepsALaterSave() async throws {
        manager.reconcile(installed: nil)
        loader.seedStylePacks()
        let two = stages(2)
        let task = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion()
        try await task.value
        XCTAssertTrue(loader.removedIds.isEmpty, "the launch reconcile has no claim on a later save")
        XCTAssertEqual(manager.status(for: "camino-frances", stages: two), .saved(bytes: 200_000))
    }

    /// The store can answer in the middle of a save, long after the launch
    /// that asked. The save is the newer truth about what belongs on disk.
    func testASaveCancelsAPendingLaunchSweep() async throws {
        loader.withholdsRegions = true
        manager.reconcile(installed: nil)
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(2)) }
        await untilPending()
        loader.completeNextRegion(); await untilPending()
        loader.completeNextRegion()
        try await task.value

        loader.releaseRegions()
        XCTAssertTrue(loader.removedIds.isEmpty, "the save outranks a launch sweep still waiting on the store")
    }
}
