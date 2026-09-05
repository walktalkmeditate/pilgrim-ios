import XCTest
@testable import Pilgrim

/// Route packages the checked-in fixtures do not carry, built by JSON
/// mutation rather than more files on disk. `route.json` and every
/// `stage-NN.json` are always mutated together: the download cross-checks a
/// stage's own `count` and `name` against the route file, exactly as the
/// dataset build keeps the two in step.
extension PilgrimagePackageManagerTests {

    /// A three-stage variant of the fixture route: only the rollback cases
    /// need a previous install larger than the package replacing it.
    func stubThreeStagePackage(release: String = "v1.7.0") throws {
        StubURLProtocol.stub(url: try url("route.json", release: release), body: try threeStageRoute())
        for index in 0...1 {
            StubURLProtocol.stub(url: try url(PilgrimagePackageManager.stageFileName(index), release: release),
                                 body: try stageFixture(index, count: 3))
        }
        StubURLProtocol.stub(url: try url("stage-02.json", release: release), body: try thirdStage())
    }

    var entryWithThreeStages: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-frances", name: entry.name, names: [:], country: "ES",
                               region: "Europe", distanceKm: 46.1, tradition: "christian",
                               stageCount: 3, bytes: 300_000)
    }

    /// A one-stage variant: stage 0 kept under its own name — the identity a
    /// ledger reconciliation recognizes — and stage 1 simply gone.
    func stubOneStagePackage(release: String) throws {
        StubURLProtocol.stub(url: try url("route.json", release: release), body: try oneStageRoute())
        StubURLProtocol.stub(url: try url("stage-00.json", release: release), body: try stageFixture(0, count: 1))
    }

    var entryWithOneStage: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-frances", name: entry.name, names: [:], country: "ES",
                               region: "Europe", distanceKm: 24.2, tradition: "christian",
                               stageCount: 1, bytes: 100_000)
    }

    /// Both stages walked, so a reconciliation test can show one entry
    /// surviving and the other dropped.
    func seedTwoStageLedger() {
        var led = PilgrimageLedger(routeId: "camino-frances")
        led.record(stageIndex: 0, name: "Saint-Jean-Pied-de-Port to Roncesvalles", distanceKm: 24.2,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        led.record(stageIndex: 1, name: "Roncesvalles to Zubiri", distanceKm: 21.9,
                   outcome: HonorStageOutcome(progressFrac: 1, arrived: true), at: Date())
        ledgers.save(led)
    }

    // MARK: - JSON mutation

    /// A checked-in stage file re-counted for a route of a different length.
    /// Nothing else moves: the name the route file names it by has to survive.
    private func stageFixture(_ index: Int, count: Int) throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: try PilgrimageFixtures.data(PilgrimagePackageManager.stageFileName(index))) as? [String: Any])
        var stage = try XCTUnwrap(obj["stage"] as? [String: Any])
        stage["count"] = count
        obj["stage"] = stage
        return try JSONSerialization.data(withJSONObject: obj)
    }

    private func threeStageRoute() throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("route.json")) as? [String: Any])
        var stages = try XCTUnwrap(obj["stages"] as? [[String: Any]])
        stages.append([
            "index": 2, "name": Self.thirdStageName, "distanceKm": 20.4, "gainMeters": 128.0,
            "hours": ["min": 5.0, "max": 6.0], "difficulty": "easy"
        ])
        obj["stageCount"] = 3
        obj["stages"] = stages
        return try JSONSerialization.data(withJSONObject: obj)
    }

    private func oneStageRoute() throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("route.json")) as? [String: Any])
        var stages = try XCTUnwrap(obj["stages"] as? [[String: Any]])
        stages.removeLast()
        obj["stageCount"] = 1
        obj["stages"] = stages
        return try JSONSerialization.data(withJSONObject: obj)
    }

    /// `stage-01.json` reshaped into the third stage of `threeStageRoute()`,
    /// under the name that route file gives index 2.
    private func thirdStage() throws -> Data {
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try PilgrimageFixtures.data("stage-01.json")) as? [String: Any])
        var stage = try XCTUnwrap(obj["stage"] as? [String: Any])
        obj["id"] = "pilgrimage:camino-frances:2"
        stage["index"] = 2
        stage["count"] = 3
        stage["name"] = Self.thirdStageName
        obj["stage"] = stage
        return try JSONSerialization.data(withJSONObject: obj)
    }

    private static let thirdStageName = "Zubiri to Pamplona"
}
