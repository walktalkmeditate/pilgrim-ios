import XCTest
@testable import Pilgrim

final class VoiceGuideManifestTests: XCTestCase {

    private let sampleJSON = """
    {
      "version": "2026-03-17T00:00:00Z",
      "packs": [
        {
          "id": "breeze",
          "version": "1",
          "name": "Breeze",
          "tagline": "A gentle questioner",
          "description": "Soft open-ended questions",
          "theme": "presence",
          "iconName": "wind",
          "type": "voiceGuide",
          "walkTypes": ["wander"],
          "scheduling": {
            "densityMinSec": 720,
            "densityMaxSec": 1080,
            "minSpacingSec": 600,
            "initialDelaySec": 300,
            "walkEndBufferSec": 300
          },
          "totalDurationSec": 120.5,
          "totalSizeBytes": 50000,
          "prompts": [
            {
              "id": "breeze_01",
              "seq": 1,
              "durationSec": 10.5,
              "fileSizeBytes": 5000,
              "r2Key": "voiceguide/breeze/breeze_01.aac"
            },
            {
              "id": "breeze_02",
              "seq": 2,
              "durationSec": 8.3,
              "fileSizeBytes": 4000,
              "r2Key": "voiceguide/breeze/breeze_02.aac"
            }
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    func testDecodeManifest() throws {
        let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
        XCTAssertEqual(manifest.version, "2026-03-17T00:00:00Z")
        XCTAssertEqual(manifest.packs.count, 1)
    }

    func testDecodePack() throws {
        let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
        let pack = manifest.packs[0]

        XCTAssertEqual(pack.id, "breeze")
        XCTAssertEqual(pack.name, "Breeze")
        XCTAssertEqual(pack.tagline, "A gentle questioner")
        XCTAssertEqual(pack.iconName, "wind")
        XCTAssertEqual(pack.type, "voiceGuide")
        XCTAssertEqual(pack.walkTypes, ["wander"])
        XCTAssertEqual(pack.totalDurationSec, 120.5)
        XCTAssertEqual(pack.totalSizeBytes, 50000)
    }

    func testDecodeScheduling() throws {
        let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
        let scheduling = manifest.packs[0].scheduling

        XCTAssertEqual(scheduling.densityMinSec, 720)
        XCTAssertEqual(scheduling.densityMaxSec, 1080)
        XCTAssertEqual(scheduling.minSpacingSec, 600)
        XCTAssertEqual(scheduling.initialDelaySec, 300)
        XCTAssertEqual(scheduling.walkEndBufferSec, 300)
    }

    func testDecodePrompts() throws {
        let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
        let prompts = manifest.packs[0].prompts

        XCTAssertEqual(prompts.count, 2)
        XCTAssertEqual(prompts[0].id, "breeze_01")
        XCTAssertEqual(prompts[0].seq, 1)
        XCTAssertEqual(prompts[0].durationSec, 10.5)
        XCTAssertEqual(prompts[0].fileSizeBytes, 5000)
        XCTAssertEqual(prompts[0].r2Key, "voiceguide/breeze/breeze_01.aac")
    }

    func testRoundTrip() throws {
        let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: sampleJSON)
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(VoiceGuideManifest.self, from: encoded)

        XCTAssertEqual(decoded.version, manifest.version)
        XCTAssertEqual(decoded.packs.count, manifest.packs.count)
        XCTAssertEqual(decoded.packs[0].id, manifest.packs[0].id)
        XCTAssertEqual(decoded.packs[0].prompts.count, manifest.packs[0].prompts.count)
    }

    func testEmptyPacksDecodes() throws {
        let json = """
        {"version": "1", "packs": []}
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(VoiceGuideManifest.self, from: json)
        XCTAssertTrue(manifest.packs.isEmpty)
    }
}
