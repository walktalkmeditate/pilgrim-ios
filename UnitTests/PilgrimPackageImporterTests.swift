import XCTest
import ZIPFoundation
@testable import Pilgrim

/// Integration coverage for `PilgrimPackageImporter.unpackAndDecode`.
/// Builds a fixture `.pilgrim` archive in a tempDir, runs the importer's
/// parse pipeline against it, and verifies the round-trip results — all
/// without going through `DataManager.saveWalks`, which would require a
/// live CoreStore stack.
final class PilgrimPackageImporterTests: XCTestCase {

    private var fixtureURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in fixtureURLs {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureURLs.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Photos absent (pre-reliquary archive shape)

    func testUnpackAndDecode_archiveWithoutPhotosKey_decodesEmptyWalkPhotos() throws {
        let walk = makeMinimalPilgrimWalk(photos: nil)
        let archive = try buildFixtureArchive(walks: [walk], includePhotosDirectory: false)

        let (decoded, _) = try PilgrimPackageImporter.unpackAndDecode(from: archive)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(
            decoded.first?.walkPhotos.isEmpty ?? false,
            "Pre-reliquary archives (no photos key) must decode to empty walkPhotos, not crash"
        )
    }

    // MARK: - Photos present, embedded directory present

    func testUnpackAndDecode_archiveWithPhotosKey_populatesWalkPhotos() throws {
        let photo = PilgrimPhoto(
            localIdentifier: "ABC-123/L0/001",
            capturedAt: Date(timeIntervalSince1970: 1710001000),
            capturedLat: 35.0116,
            capturedLng: 135.7681,
            keptAt: Date(timeIntervalSince1970: 1710002000),
            embeddedPhotoFilename: "ABC-123_L0_001.jpg"
        )
        let walk = makeMinimalPilgrimWalk(photos: [photo])
        let archive = try buildFixtureArchive(
            walks: [walk],
            includePhotosDirectory: true
        )

        let (decoded, _) = try PilgrimPackageImporter.unpackAndDecode(from: archive)

        let imported = try XCTUnwrap(decoded.first)
        XCTAssertEqual(imported.walkPhotos.count, 1)
        let restoredPhoto = try XCTUnwrap(imported.walkPhotos.first)
        XCTAssertEqual(restoredPhoto.localIdentifier, "ABC-123/L0/001")
        XCTAssertEqual(restoredPhoto.capturedLat, 35.0116, accuracy: 0.0001)
        XCTAssertEqual(restoredPhoto.capturedLng, 135.7681, accuracy: 0.0001)
        XCTAssertEqual(
            restoredPhoto.capturedAt.timeIntervalSince1970,
            1710001000,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredPhoto.keptAt.timeIntervalSince1970,
            1710002000,
            accuracy: 0.001
        )
        // TempWalkPhoto has no embeddedPhotoFilename field by design —
        // the app side stores metadata only, photos are viewer-only.
        // This assertion documents the intentional information loss.
    }

    // MARK: - photos/ directory present in ZIP but importer ignores its bytes

    func testUnpackAndDecode_photosDirectoryPresent_doesNotCrash() throws {
        // Builds an archive that includes a photos/ directory with a
        // dummy JPEG. The importer must not try to read or relocate
        // these bytes — they're viewer-only. We just verify the parse
        // succeeds and returns the expected walks.
        let photo = PilgrimPhoto(
            localIdentifier: "X",
            capturedAt: Date(timeIntervalSince1970: 1000),
            capturedLat: 0,
            capturedLng: 0,
            keptAt: Date(timeIntervalSince1970: 2000),
            embeddedPhotoFilename: "X.jpg"
        )
        let walk = makeMinimalPilgrimWalk(photos: [photo])
        let archive = try buildFixtureArchive(
            walks: [walk],
            includePhotosDirectory: true,
            photoFileContents: Data(repeating: 0xFF, count: 1024) // dummy "JPEG" bytes
        )

        let (decoded, _) = try PilgrimPackageImporter.unpackAndDecode(from: archive)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.walkPhotos.count, 1)
    }

    // MARK: - Forward-compat: archive with photos/ but no `photos` JSON key

    func testUnpackAndDecode_photosDirectoryWithoutJSONField_stillSucceeds() throws {
        // Theoretical edge case: someone hand-crafts an archive with a
        // photos/ directory but doesn't populate the walk JSONs. The
        // importer should still parse the walks correctly, treating
        // the photos/ directory as orphan bytes that get cleaned up
        // with tempDir.
        let walk = makeMinimalPilgrimWalk(photos: nil)
        let archive = try buildFixtureArchive(
            walks: [walk],
            includePhotosDirectory: true,
            photoFileContents: Data(repeating: 0x00, count: 256)
        )

        let (decoded, _) = try PilgrimPackageImporter.unpackAndDecode(from: archive)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertTrue(decoded.first?.walkPhotos.isEmpty ?? false)
    }

    // MARK: - Fixture builder

    /// Constructs a minimal valid `.pilgrim` archive on disk in
    /// `FileManager.default.temporaryDirectory`, returning its URL. The
    /// returned URL is registered for tearDown cleanup.
    private func buildFixtureArchive(
        walks: [PilgrimWalk],
        includePhotosDirectory: Bool,
        photoFileContents: Data = Data(repeating: 0xFF, count: 256)
    ) throws -> URL {
        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-importer-test-\(UUID().uuidString)")
        let walksDir = stagingDir.appendingPathComponent("walks")
        try fm.createDirectory(at: walksDir, withIntermediateDirectories: true)

        // Cleanup the staging dir even if zipItem throws — without
        // this defer, a failed test would leak a tempDir on every run.
        defer { try? fm.removeItem(at: stagingDir) }

        let encoder = PilgrimDateCoding.makeEncoder()

        for walk in walks {
            let data = try encoder.encode(walk)
            let walkFile = walksDir.appendingPathComponent("\(walk.id.uuidString).json")
            try data.write(to: walkFile)
        }

        // Minimal manifest the importer can decode (schemaVersion check
        // is the only field PilgrimPackageImporter inspects today).
        let manifest = PilgrimManifest(
            schemaVersion: "1.0",
            exportDate: Date(timeIntervalSince1970: 1710000000),
            appVersion: "test",
            walkCount: walks.count,
            preferences: PilgrimPreferences(
                distanceUnit: "km",
                altitudeUnit: "m",
                speedUnit: "km/h",
                energyUnit: "kcal",
                celestialAwareness: false,
                zodiacSystem: "tropical",
                beginWithIntention: false
            ),
            customPromptStyles: [],
            intentions: [],
            events: []
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: stagingDir.appendingPathComponent("manifest.json"))

        // schema.json is bundled but not read by the importer — the
        // builder always writes it, so we mirror that for fidelity.
        let schemaData = Data(PilgrimPackageSchema.json.utf8)
        try schemaData.write(to: stagingDir.appendingPathComponent("schema.json"))

        if includePhotosDirectory {
            let photosDir = stagingDir.appendingPathComponent("photos")
            try fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
            // Write a single dummy file. The importer must never try to
            // open or read it — that's the test invariant.
            try photoFileContents.write(to: photosDir.appendingPathComponent("dummy.jpg"))
        }

        let archiveURL = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-importer-test-\(UUID().uuidString).pilgrim")
        try? fm.removeItem(at: archiveURL)
        try fm.zipItem(at: stagingDir, to: archiveURL, shouldKeepParent: false)

        // Sanity check: a 0-byte archive would mean ZIPFoundation silently
        // failed. The importer would then report "invalid package" with
        // no clue that the fixture builder is broken. Catch it here with
        // a clearer diagnosis.
        let archiveSize = (try? fm.attributesOfItem(atPath: archiveURL.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(
            archiveSize,
            0,
            "Fixture builder produced a 0-byte archive — ZIPFoundation may have silently failed"
        )

        fixtureURLs.append(archiveURL)
        return archiveURL
    }

    private func makeMinimalPilgrimWalk(photos: [PilgrimPhoto]?) -> PilgrimWalk {
        PilgrimWalk(
            schemaVersion: "1.0",
            id: UUID(),
            type: "walking",
            startDate: Date(timeIntervalSince1970: 1710000000),
            endDate: Date(timeIntervalSince1970: 1710003600),
            stats: PilgrimStats(
                distance: 1000, steps: 1500,
                activeDuration: 3600, pauseDuration: 0,
                ascent: 0, descent: 0,
                burnedEnergy: nil,
                talkDuration: 0, meditateDuration: 0
            ),
            weather: nil,
            route: GeoJSONFeatureCollection(features: []),
            pauses: [],
            activities: [],
            voiceRecordings: [],
            intention: nil,
            reflection: nil,
            heartRates: [],
            workoutEvents: [],
            favicon: nil,
            isRace: false,
            isUserModified: false,
            finishedRecording: true,
            photos: photos
        )
    }
}
