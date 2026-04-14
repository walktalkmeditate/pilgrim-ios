import XCTest
@testable import Pilgrim

/// Codable + converter coverage for the Stage 5 `PilgrimPhoto` export shape
/// and its `includePhotos:` gate. Split out of `PilgrimPackageModelTests` and
/// `PilgrimPackageConverterTests` so those files stay under SwiftLint's
/// file-length threshold.
final class PilgrimPackagePhotoTests: XCTestCase {

    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        encoder = PilgrimDateCoding.makeEncoder()
        decoder = PilgrimDateCoding.makeDecoder()
    }

    // MARK: - PilgrimPhoto Codable

    func testPhoto_roundTrip() throws {
        let photo = PilgrimPhoto(
            localIdentifier: "ABC-123/L0/001",
            capturedAt: Date(timeIntervalSince1970: 1710000500.5),
            capturedLat: 35.0116,
            capturedLng: 135.7681,
            keptAt: Date(timeIntervalSince1970: 1710100000),
            embeddedPhotoFilename: "ABC-123_L0_001.jpg"
        )

        let decoded = try roundTrip(photo)
        XCTAssertEqual(decoded.localIdentifier, "ABC-123/L0/001")
        XCTAssertEqual(
            decoded.capturedAt.timeIntervalSince1970,
            1710000500.5,
            accuracy: 0.001
        )
        XCTAssertEqual(decoded.capturedLat, 35.0116, accuracy: 0.0001)
        XCTAssertEqual(decoded.capturedLng, 135.7681, accuracy: 0.0001)
        XCTAssertEqual(
            decoded.keptAt.timeIntervalSince1970,
            1710100000,
            accuracy: 0.001
        )
        XCTAssertEqual(decoded.embeddedPhotoFilename, "ABC-123_L0_001.jpg")
    }

    func testPhoto_nilEmbeddedFilename() throws {
        let photo = PilgrimPhoto(
            localIdentifier: "XYZ/123",
            capturedAt: Date(timeIntervalSince1970: 1710000000),
            capturedLat: 40.0,
            capturedLng: -75.0,
            keptAt: Date(timeIntervalSince1970: 1710000100),
            embeddedPhotoFilename: nil
        )

        let decoded = try roundTrip(photo)
        XCTAssertNil(decoded.embeddedPhotoFilename)
    }

    // MARK: - PilgrimWalk with photos

    func testWalk_roundTripWithPhotos() throws {
        let photo = PilgrimPhoto(
            localIdentifier: "P1",
            capturedAt: Date(timeIntervalSince1970: 1500),
            capturedLat: 10,
            capturedLng: 20,
            keptAt: Date(timeIntervalSince1970: 2500),
            embeddedPhotoFilename: nil
        )
        let walk = makeMinimalWalk(photos: [photo])

        let decoded = try roundTrip(walk)
        XCTAssertEqual(decoded.photos?.count, 1)
        XCTAssertEqual(decoded.photos?.first?.localIdentifier, "P1")
        XCTAssertEqual(decoded.photos?.first?.capturedLat, 10)
        XCTAssertEqual(decoded.photos?.first?.capturedLng, 20)
    }

    func testWalk_decodesOlderFormatWithoutPhotosKey() throws {
        // Older .pilgrim files (pre-reliquary) don't have a "photos" key.
        // Decode them by stripping the key from an encoded walk and confirming
        // the result has photos == nil.
        let walk = makeMinimalWalk()
        let data = try encoder.encode(walk)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json.removeValue(forKey: "photos")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(PilgrimWalk.self, from: stripped)
        XCTAssertNil(decoded.photos)
    }

    func testWalk_photosNil_omitsKeyFromJSON() throws {
        // When the user opts out of photo export, the converter passes
        // `photos: nil` to PilgrimWalk, and the encoded JSON must omit the
        // "photos" key entirely. This is what lets a "photos OFF" export stay
        // byte-identical to the pre-reliquary format.
        let walk = makeMinimalWalk()
        let data = try encoder.encode(walk)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(
            json["photos"],
            "Encoded walk with nil photos must omit the 'photos' key"
        )
    }

    // MARK: - Converter forward (Walk -> PilgrimWalk)

    func testConvert_default_omitsPhotos() {
        let photo = TempWalkPhoto(
            uuid: UUID(),
            localIdentifier: "A1",
            capturedAt: Date(timeIntervalSince1970: 1710001000),
            capturedLat: 35.0,
            capturedLng: 135.0,
            keptAt: Date(timeIntervalSince1970: 1710002000)
        )
        let walk = makeTestWalk(walkPhotos: [photo])
        let pw = PilgrimPackageConverter.convert(
            walk: walk,
            system: .tropical,
            celestialEnabled: false
        )!

        XCTAssertNil(
            pw.photos,
            "Default convert (no includePhotos) must omit photos so exports stay byte-identical to the pre-reliquary format"
        )
    }

    func testConvert_includePhotosFalse_nilPhotos() {
        let photo = TempWalkPhoto(
            uuid: UUID(),
            localIdentifier: "A1",
            capturedAt: Date(timeIntervalSince1970: 1710001000),
            capturedLat: 35.0,
            capturedLng: 135.0,
            keptAt: Date(timeIntervalSince1970: 1710002000)
        )
        let walk = makeTestWalk(walkPhotos: [photo])
        let pw = PilgrimPackageConverter.convert(
            walk: walk,
            system: .tropical,
            celestialEnabled: false,
            includePhotos: false
        )!

        XCTAssertNil(pw.photos)
    }

    func testConvert_includePhotosTrue_populatesMetadata() throws {
        let photo = TempWalkPhoto(
            uuid: UUID(),
            localIdentifier: "ABC/L0/001",
            capturedAt: Date(timeIntervalSince1970: 1710001000),
            capturedLat: 35.0116,
            capturedLng: 135.7681,
            keptAt: Date(timeIntervalSince1970: 1710002000)
        )
        let walk = makeTestWalk(walkPhotos: [photo])
        let pw = PilgrimPackageConverter.convert(
            walk: walk,
            system: .tropical,
            celestialEnabled: false,
            includePhotos: true
        )!

        let exportedPhoto = try XCTUnwrap(pw.photos?.first)
        XCTAssertEqual(pw.photos?.count, 1)
        XCTAssertEqual(exportedPhoto.localIdentifier, "ABC/L0/001")
        XCTAssertEqual(exportedPhoto.capturedLat, 35.0116, accuracy: 0.0001)
        XCTAssertEqual(exportedPhoto.capturedLng, 135.7681, accuracy: 0.0001)
        // embeddedPhotoFilename stays nil at the converter layer; Stage 5c
        // (the builder) sets it when it actually writes the bytes.
        XCTAssertNil(exportedPhoto.embeddedPhotoFilename)
    }

    func testConvert_includePhotosTrue_emptyArrayForWalkWithoutPhotos() {
        let walk = makeTestWalk()
        let pw = PilgrimPackageConverter.convert(
            walk: walk,
            system: .tropical,
            celestialEnabled: false,
            includePhotos: true
        )!

        // includePhotos: true with zero pinned photos → empty array, not nil.
        // This distinguishes "opted in but nothing to share" from "opted out".
        XCTAssertEqual(pw.photos?.count, 0)
    }

    // MARK: - Converter reverse (PilgrimWalk -> TempWalk)

    func testConvertToTemp_nilPhotos_emptyWalkPhotos() {
        let exported = makeMinimalExportedWalk(photos: nil)
        let temp = PilgrimPackageConverter.convertToTemp(walk: exported)
        XCTAssertTrue(temp.walkPhotos.isEmpty)
    }

    func testConvertToTemp_preservesPhotos() throws {
        let photoID = "XYZ-456/L0/042"
        let capturedAt = Date(timeIntervalSince1970: 1710001500.5)
        let keptAt = Date(timeIntervalSince1970: 1710100000)
        let exportedPhoto = PilgrimPhoto(
            localIdentifier: photoID,
            capturedAt: capturedAt,
            capturedLat: 43.7696,
            capturedLng: 11.2558,
            keptAt: keptAt,
            embeddedPhotoFilename: nil
        )
        let exported = makeMinimalExportedWalk(photos: [exportedPhoto])

        let temp = PilgrimPackageConverter.convertToTemp(walk: exported)
        let restoredPhoto = try XCTUnwrap(temp.walkPhotos.first)
        XCTAssertEqual(temp.walkPhotos.count, 1)
        XCTAssertEqual(restoredPhoto.localIdentifier, photoID)
        XCTAssertEqual(
            restoredPhoto.capturedAt.timeIntervalSince1970,
            capturedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(restoredPhoto.capturedLat, 43.7696, accuracy: 0.0001)
        XCTAssertEqual(restoredPhoto.capturedLng, 11.2558, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    private func makeMinimalWalk(photos: [PilgrimPhoto]? = nil) -> PilgrimWalk {
        PilgrimWalk(
            schemaVersion: "1.0",
            id: UUID(),
            type: "walking",
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            stats: PilgrimStats(
                distance: 100, steps: nil,
                activeDuration: 60, pauseDuration: 0,
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

    private func makeMinimalExportedWalk(photos: [PilgrimPhoto]?) -> PilgrimWalk {
        makeMinimalWalk(photos: photos)
    }

    private func makeTestWalk(walkPhotos: [TempWalkPhoto] = []) -> TempWalk {
        TempWalk(
            uuid: UUID(),
            workoutType: .walking,
            distance: 5000.0,
            steps: 6500,
            startDate: Date(timeIntervalSince1970: 1710000000),
            endDate: Date(timeIntervalSince1970: 1710003600),
            burnedEnergy: 250.0,
            isRace: false,
            comment: "Be present",
            isUserModified: false,
            healthKitUUID: nil,
            finishedRecording: true,
            ascend: 50.0,
            descend: 45.0,
            activeDuration: 3600.0,
            pauseDuration: 120.0,
            dayIdentifier: "20240309",
            talkDuration: 180.0,
            meditateDuration: 300.0,
            heartRates: [],
            routeData: [],
            pauses: [],
            workoutEvents: [],
            voiceRecordings: [],
            activityIntervals: [],
            favicon: nil,
            waypoints: [],
            walkPhotos: walkPhotos
        )
    }
}
