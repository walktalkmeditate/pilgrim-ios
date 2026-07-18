// UnitTests/CollectiveRouteCatalogServiceTests.swift
import XCTest
@testable import Pilgrim

// MARK: - Fixtures

/// A whole artifact whose version and single route id are both readable back off
/// the published catalog, so "which tier won" is answerable from the service's
/// own state without reaching for the file system.
private func artifactJSON(version: String, routeId: String) -> Data {
    Data("""
    {
      "version": "\(version)",
      "pilgrimages": [
        { "id": "\(routeId)", "kind": "route", "nameEn": "Route", "companyLine": "Some walked it.", "km": 100 }
      ],
      "horizons": []
    }
    """.utf8)
}

/// The service's cache file name, spelled out rather than read off the service.
/// If the on-disk contract moves, these tests should fail rather than follow it —
/// a renamed cache file silently orphans every already-installed pilgrim's copy.
private let cacheFileName = "routes.json"

// MARK: - Three-tier load precedence

/// Cache, then bundled bootstrap, then nothing. This is the behaviour most
/// likely to regress silently: every tier produces *a* catalog, so a broken
/// precedence looks like a working app serving stale routes.
///
/// Every test here awaits `initialLoad` before returning, including the one
/// asserting pre-load behaviour. The detached load resolves its bootstrap path
/// off the main thread, and teardown deletes the directory that path points
/// into — leaving the task to run against a directory that no longer exists.
final class CollectiveRouteCatalogServiceLoadTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeBootstrap() throws -> URL {
        let url = tempDir.appendingPathComponent("bootstrap.json")
        try artifactJSON(version: "bootstrap-v1", routeId: "from-bootstrap").write(to: url)
        return url
    }

    private func writeCache(_ data: Data) throws {
        try data.write(to: tempDir.appendingPathComponent(cacheFileName))
    }

    private func makeService(bootstrap: URL) -> CollectiveRouteCatalogService {
        CollectiveRouteCatalogService(
            catalogDirectory: tempDir,
            bootstrapCatalogURL: { bootstrap },
            fetchRemoteData: { nil }
        )
    }

    @MainActor
    func testInitialLoad_withNoCachedFile_servesTheBundledBootstrap() async throws {
        let service = makeService(bootstrap: try writeBootstrap())

        await service.initialLoad?.value

        XCTAssertEqual(service.catalog?.version, "bootstrap-v1")
        XCTAssertEqual(service.catalog?.entries.map(\.id), ["from-bootstrap"])
    }

    @MainActor
    func testInitialLoad_cachedFileWinsOverTheBootstrap() async throws {
        let bootstrap = try writeBootstrap()
        try writeCache(artifactJSON(version: "cache-v7", routeId: "from-cache"))
        let service = makeService(bootstrap: bootstrap)

        await service.initialLoad?.value

        XCTAssertEqual(service.catalog?.version, "cache-v7")
        XCTAssertEqual(service.catalog?.entries.map(\.id), ["from-cache"],
                       "The bootstrap must not be consulted when a cached catalog exists")
    }

    // A truncated write or a half-flushed file should cost the pilgrim one
    // launch's freshness, not the whole feature.
    @MainActor
    func testInitialLoad_corruptCachedFile_fallsBackToTheBootstrap() async throws {
        let bootstrap = try writeBootstrap()
        try writeCache(Data("not json".utf8))
        let service = makeService(bootstrap: bootstrap)

        await service.initialLoad?.value

        XCTAssertEqual(service.catalog?.entries.map(\.id), ["from-bootstrap"])
    }

    // The test holds the main actor until it suspends, and the load publishes
    // through `MainActor.run` — so the pre-load state below is deterministic
    // rather than a race the test happens to win.
    @MainActor
    func testLookupsBeforeInitialLoadCompletes_returnNothingWithoutBlocking() async throws {
        let service = makeService(bootstrap: try writeBootstrap())
        let date = DateFactory.makeDate(2026, 10, 7)

        XCTAssertNil(service.catalog)
        XCTAssertNil(service.dailyLine(for: date, collectiveKm: 694.5))
        XCTAssertNil(service.contributionLine(for: date, walkKm: 4.2))

        await service.initialLoad?.value
    }
}

// MARK: - Remote sync

final class CollectiveRouteCatalogServiceSyncTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var cacheURL: URL {
        tempDir.appendingPathComponent(cacheFileName)
    }

    /// Boots the service off a bootstrap at `bootstrap-v1`, then runs one sync
    /// against `remote` and returns once both the publish and the cache write
    /// have landed.
    @MainActor
    private func syncedService(remote: Data?) async throws -> CollectiveRouteCatalogService {
        let bootstrapURL = tempDir.appendingPathComponent("bootstrap.json")
        try artifactJSON(version: "bootstrap-v1", routeId: "from-bootstrap").write(to: bootstrapURL)

        let service = CollectiveRouteCatalogService(
            catalogDirectory: tempDir,
            bootstrapCatalogURL: { bootstrapURL },
            fetchRemoteData: { remote }
        )
        service.syncIfNeeded()
        await service.syncTask?.value
        return service
    }

    @MainActor
    func testSync_remoteWithADifferentVersion_replacesTheCacheAndPublishes() async throws {
        let remote = artifactJSON(version: "remote-v2", routeId: "from-remote")
        let service = try await syncedService(remote: remote)

        XCTAssertEqual(service.catalog?.version, "remote-v2")
        XCTAssertEqual(service.catalog?.entries.map(\.id), ["from-remote"])
        XCTAssertEqual(try Data(contentsOf: cacheURL), remote,
                       "The cache must hold the exact bytes the CDN served, not a re-encode")
    }

    // Same version, deliberately different contents. Comparing the published
    // entries rather than the version is what proves the sync short-circuited
    // instead of re-publishing an identical-looking catalog.
    @MainActor
    func testSync_remoteWithAnEqualVersion_leavesThePublishedCatalogUntouched() async throws {
        let service = try await syncedService(remote: artifactJSON(version: "bootstrap-v1", routeId: "from-remote"))

        XCTAssertEqual(service.catalog?.entries.map(\.id), ["from-bootstrap"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path),
                       "An unchanged version must not spend a disk write")
    }

    // Versions are content-derived and carry no ordering, so a curator reverting
    // to a prior artifact publishes a "lower" one. Comparing for inequality is
    // what lets that rollback reach devices at all.
    @MainActor
    func testSync_remoteWithAnOlderVersion_stillApplies() async throws {
        let service = try await syncedService(remote: artifactJSON(version: "bootstrap-v0", routeId: "rolled-back"))

        XCTAssertEqual(service.catalog?.version, "bootstrap-v0")
        XCTAssertEqual(service.catalog?.entries.map(\.id), ["rolled-back"])
    }

    @MainActor
    func testSync_failedNetworkResponse_leavesTheExistingCatalogInPlace() async throws {
        let service = try await syncedService(remote: nil)

        XCTAssertEqual(service.catalog?.version, "bootstrap-v1")
        XCTAssertEqual(service.catalog?.entries.map(\.id), ["from-bootstrap"])
    }

    @MainActor
    func testSync_undecodableRemotePayload_leavesTheExistingCatalogInPlace() async throws {
        let service = try await syncedService(remote: Data("not json".utf8))

        XCTAssertEqual(service.catalog?.version, "bootstrap-v1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path),
                       "A payload the app cannot read must never reach the cache")
    }

    // Nothing awaits `syncIfNeeded`, so a stuck flag would freeze the catalog
    // for the rest of the process with no visible symptom.
    @MainActor
    func testSync_clearsTheSyncingFlagWhenItFinishes() async throws {
        let service = try await syncedService(remote: artifactJSON(version: "remote-v2", routeId: "from-remote"))

        XCTAssertFalse(service.isSyncing)
    }
}
