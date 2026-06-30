// UnitTests/WhisperManifestServiceTests.swift
import XCTest
@testable import Pilgrim

final class WhisperManifestDecodingTests: XCTestCase {

    func testDecodes_minimalManifest() throws {
        let json = Data("""
        {
          "version": 1,
          "whispers": [
            {
              "id": "presence-1",
              "title": "What do you see right now?",
              "category": "presence",
              "audioFileName": "whisper-presence-1",
              "durationSec": 6,
              "retiredAt": null
            }
          ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.whispers.count, 1)
        XCTAssertEqual(manifest.whispers.first?.id, "presence-1")
        XCTAssertNil(manifest.whispers.first?.retiredAt)
    }

    func testDecodes_dropsUnknownCategoryWithoutFailing() throws {
        let json = Data("""
        {
          "version": 3,
          "whispers": [
            {
              "id": "presence-1",
              "title": "Good",
              "category": "presence",
              "audioFileName": "whisper-presence-1",
              "durationSec": 6,
              "retiredAt": null
            },
            {
              "id": "devotion-1",
              "title": "Unknown category",
              "category": "devotion",
              "audioFileName": "whisper-devotion-1",
              "durationSec": 5,
              "retiredAt": null
            },
            {
              "id": "play-1",
              "title": "Also good",
              "category": "play",
              "audioFileName": "whisper-play-1",
              "durationSec": 4,
              "retiredAt": null
            }
          ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertEqual(manifest.version, 3)
        XCTAssertEqual(manifest.whispers.count, 2, "Unknown 'devotion' entry should be silently dropped")
        XCTAssertEqual(manifest.whispers[0].id, "presence-1")
        XCTAssertEqual(manifest.whispers[1].id, "play-1")
    }

    func testDecodes_dropsMalformedEntryWithoutFailing() throws {
        let json = Data("""
        {
          "version": 1,
          "whispers": [
            {
              "id": "presence-1",
              "title": "Good",
              "category": "presence",
              "audioFileName": "whisper-presence-1",
              "durationSec": 6,
              "retiredAt": null
            },
            {
              "BROKEN": true
            },
            {
              "id": "play-1",
              "title": "Also good",
              "category": "play",
              "audioFileName": "whisper-play-1",
              "durationSec": 4,
              "retiredAt": null
            }
          ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertEqual(manifest.whispers.count, 2, "Malformed entry should be silently dropped")
    }

    func testDecodes_retiredAtAsISO8601() throws {
        let json = Data("""
        {
          "version": 2,
          "whispers": [
            {
              "id": "courage-9",
              "title": "Old phrase",
              "category": "courage",
              "audioFileName": "whisper-courage-9",
              "durationSec": 5,
              "retiredAt": "2026-04-11T00:00:00Z"
            }
          ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertNotNil(manifest.whispers.first?.retiredAt)
    }
}

final class WhisperManifestFilteringTests: XCTestCase {

    private func makeManifest() -> WhisperManifest {
        WhisperManifest(
            version: 1,
            whispers: [
                WhisperDefinition(id: "gratitude-1", title: "Alive", category: .gratitude, audioFileName: "whisper-gratitude-1", durationSec: 5, retiredAt: nil),
                WhisperDefinition(id: "gratitude-2", title: "Old", category: .gratitude, audioFileName: "whisper-gratitude-2", durationSec: 5, retiredAt: Date(timeIntervalSince1970: 1_700_000_000)),
                WhisperDefinition(id: "play-1", title: "Skip", category: .play, audioFileName: "whisper-play-1", durationSec: 4, retiredAt: nil)
            ]
        )
    }

    func testWhispersInCategory_includesRetired() {
        let manifest = makeManifest()
        let results = manifest.whispers(in: .gratitude)
        XCTAssertEqual(results.count, 2, "whispers(in:) should return retired too")
    }

    func testPlaceableWhispersInCategory_excludesRetired() {
        let manifest = makeManifest()
        let placeable = manifest.placeableWhispers(in: .gratitude)
        XCTAssertEqual(placeable.count, 1)
        XCTAssertEqual(placeable.first?.id, "gratitude-1")
    }

    func testWhisperWithId_findsExisting() {
        let manifest = makeManifest()
        let hit = manifest.whisper(withId: "play-1")
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.category, .play)
    }

    func testWhisperWithId_returnsNilForMissing() {
        let manifest = makeManifest()
        XCTAssertNil(manifest.whisper(withId: "does-not-exist"))
    }
}

final class WhisperManifestPlaceableCategoriesTests: XCTestCase {

    func testPlaceableCategories_includesCategoriesWithLiveWhispers() {
        let manifest = WhisperManifest(
            version: 1,
            whispers: [
                WhisperDefinition(id: "gratitude-1", title: "x", category: .gratitude, audioFileName: "x", durationSec: 5, retiredAt: nil),
                WhisperDefinition(id: "play-1", title: "y", category: .play, audioFileName: "y", durationSec: 4, retiredAt: nil)
            ]
        )
        let categories = manifest.placeableCategories
        XCTAssertTrue(categories.contains(.gratitude))
        XCTAssertTrue(categories.contains(.play))
    }

    func testPlaceableCategories_excludesEmptyCategories() {
        let manifest = WhisperManifest(
            version: 1,
            whispers: [
                WhisperDefinition(id: "gratitude-1", title: "x", category: .gratitude, audioFileName: "x", durationSec: 5, retiredAt: nil)
            ]
        )
        let categories = manifest.placeableCategories
        XCTAssertTrue(categories.contains(.gratitude))
        XCTAssertFalse(categories.contains(.play))
        XCTAssertFalse(categories.contains(.stillness))
    }

    func testPlaceableCategories_excludesCategoriesWithOnlyRetired() {
        let retired = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = WhisperManifest(
            version: 1,
            whispers: [
                WhisperDefinition(id: "gratitude-1", title: "x", category: .gratitude, audioFileName: "x", durationSec: 5, retiredAt: retired)
            ]
        )
        let categories = manifest.placeableCategories
        XCTAssertFalse(categories.contains(.gratitude), "Category with only retired whispers should not be placeable")
    }

    func testPlaceableCategories_emptyManifest_returnsEmpty() {
        let manifest = WhisperManifest(version: 1, whispers: [])
        XCTAssertEqual(manifest.placeableCategories, [])
    }
}

final class WhisperManifestServiceAsyncInitTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeBootstrapFixture() throws -> URL {
        let json = Data("""
        {
          "version": 1,
          "whispers": [
            {
              "id": "gratitude-1",
              "title": "Alive",
              "category": "gratitude",
              "audioFileName": "whisper-gratitude-1",
              "durationSec": 5,
              "retiredAt": null
            },
            {
              "id": "gratitude-2",
              "title": "Old",
              "category": "gratitude",
              "audioFileName": "whisper-gratitude-2",
              "durationSec": 5,
              "retiredAt": "2026-04-11T00:00:00Z"
            }
          ]
        }
        """.utf8)
        let url = tempDir.appendingPathComponent("bootstrap.json")
        try json.write(to: url)
        return url
    }

    private func writeLocalManifestFixture() throws {
        let json = Data("""
        {
          "version": 7,
          "whispers": [
            {
              "id": "presence-9",
              "title": "Here",
              "category": "presence",
              "audioFileName": "whisper-presence-9",
              "durationSec": 4,
              "retiredAt": null
            }
          ]
        }
        """.utf8)
        try json.write(to: tempDir.appendingPathComponent("manifest.json"))
    }

    // The initial load publishes via the main actor, which this test holds
    // until it returns — so the pre-load state is deterministic.
    @MainActor
    func testLookupsBeforeInitialLoadCompletes_returnEmptyWithoutBlocking() throws {
        let bootstrap = try writeBootstrapFixture()
        let service = WhisperManifestService(manifestDirectory: tempDir, bootstrapManifestURL: { bootstrap })

        XCTAssertNil(service.manifest)
        XCTAssertTrue(service.whispers(for: .gratitude).isEmpty)
        XCTAssertTrue(service.placeableWhispers(for: .gratitude).isEmpty)
        XCTAssertNil(service.whisper(byId: "gratitude-1"))
        XCTAssertEqual(service.placeableCategories(), [])
    }

    @MainActor
    func testAfterInitialLoad_withNoLocalManifest_servesBootstrapCatalog() async throws {
        let bootstrap = try writeBootstrapFixture()
        let service = WhisperManifestService(manifestDirectory: tempDir, bootstrapManifestURL: { bootstrap })

        await service.initialLoad?.value

        XCTAssertEqual(service.manifest?.version, 1)
        XCTAssertEqual(service.whispers(for: .gratitude).count, 2)
        XCTAssertEqual(service.placeableWhispers(for: .gratitude).map(\.id), ["gratitude-1"],
                       "Retired whispers must stay unplaceable through the async load path")
        XCTAssertEqual(service.whisper(byId: "gratitude-2")?.category, .gratitude)
    }

    @MainActor
    func testAfterInitialLoad_localManifestWinsOverBootstrap() async throws {
        let bootstrap = try writeBootstrapFixture()
        try writeLocalManifestFixture()
        let service = WhisperManifestService(manifestDirectory: tempDir, bootstrapManifestURL: { bootstrap })

        await service.initialLoad?.value

        XCTAssertEqual(service.manifest?.version, 7)
        XCTAssertNotNil(service.whisper(byId: "presence-9"))
        XCTAssertNil(service.whisper(byId: "gratitude-1"),
                     "Bootstrap must not be consulted when a local manifest exists")
    }

    @MainActor
    func testAfterInitialLoad_corruptLocalManifest_fallsBackToBootstrap() async throws {
        let bootstrap = try writeBootstrapFixture()
        try Data("not json".utf8).write(to: tempDir.appendingPathComponent("manifest.json"))
        let service = WhisperManifestService(manifestDirectory: tempDir, bootstrapManifestURL: { bootstrap })

        await service.initialLoad?.value

        XCTAssertEqual(service.manifest?.version, 1)
        XCTAssertNotNil(service.whisper(byId: "gratitude-1"))
    }
}
