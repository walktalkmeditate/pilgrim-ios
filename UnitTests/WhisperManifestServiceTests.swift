// UnitTests/WhisperManifestServiceTests.swift
import XCTest
@testable import Pilgrim

final class WhisperManifestDecodingTests: XCTestCase {

    func testDecodes_minimalManifest() throws {
        let json = """
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
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.whispers.count, 1)
        XCTAssertEqual(manifest.whispers.first?.id, "presence-1")
        XCTAssertNil(manifest.whispers.first?.retiredAt)
    }

    func testDecodes_retiredAtAsISO8601() throws {
        let json = """
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
        """.data(using: .utf8)!

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

    func testWhispersForCategory_includesRetired() {
        let manifest = makeManifest()
        let results = manifest.whispers.filter { $0.category == .gratitude }
        XCTAssertEqual(results.count, 2, "whispers(for:) should return retired too")
    }

    func testPlaceableWhispersForCategory_excludesRetired() {
        let manifest = makeManifest()
        let placeable = manifest.whispers.filter { $0.category == .gratitude && $0.retiredAt == nil }
        XCTAssertEqual(placeable.count, 1)
        XCTAssertEqual(placeable.first?.id, "gratitude-1")
    }

    func testWhisperById_findsExisting() {
        let manifest = makeManifest()
        let hit = manifest.whispers.first { $0.id == "play-1" }
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.category, .play)
    }

    func testWhisperById_returnsNilForMissing() {
        let manifest = makeManifest()
        let miss = manifest.whispers.first { $0.id == "does-not-exist" }
        XCTAssertNil(miss)
    }
}
