import Foundation
import CoreStore
import ZIPFoundation

enum PilgrimPackageError: Error {
    case noWalksFound
    case encodingFailed
    case zipFailed(Error)
    case fileSystemError(Error)
    case invalidPackage
    case decodingFailed(Error)
    case unsupportedSchemaVersion(String)
}

/// Result of a successful `PilgrimPackageBuilder.build` call. Carries the
/// URL of the assembled `.pilgrim` archive along with the number of photos
/// that were skipped during embedding (PHAsset missing, iCloud unreachable,
/// resize/encode failure). The builder always returns a valid archive —
/// photos that fail are dropped from the walk JSON entirely rather than
/// causing the whole export to fail.
struct PilgrimPackageBuildResult {
    let url: URL
    let skippedPhotoCount: Int
}

enum PilgrimPackageBuilder {

    /// Build a `.pilgrim` archive.
    ///
    /// - parameter includePhotos: When true, the user's pinned reliquary
    ///   photos are included in each walk's JSON AND their bytes are
    ///   resized to ≤600×600, encoded as JPEG q 0.7, and written into the
    ///   archive's `photos/` directory. Defaults to `false` so any caller
    ///   that hasn't gone through the export confirmation sheet produces
    ///   a photo-free archive — defends against a future regression where
    ///   someone adds a new call site and forgets about consent.
    ///
    ///   Photos that can't be resolved (deleted in Apple Photos,
    ///   iCloud unreachable, resize failed, write failed) are dropped
    ///   from the walk JSON entirely and counted in the result's
    ///   `skippedPhotoCount`. The walk is still exported successfully
    ///   with the photos that could be resolved.
    static func build(
        includePhotos: Bool = false,
        completion: @escaping (Result<PilgrimPackageBuildResult, PilgrimPackageError>) -> Void
    ) {
        let completion = safeClosure(from: completion)

        let systemString = UserPreferences.zodiacSystem.value
        let system: ZodiacSystem = systemString == "sidereal" ? .sidereal : .tropical
        let celestialEnabled = UserPreferences.celestialAwarenessEnabled.value

        DataManager.dataStack.perform(asynchronous: { transaction -> ([Walk], [Event]) in
            let walks = try transaction.fetchAll(
                From<Walk>().orderBy(.ascending(\._startDate))
            )
            let events = try transaction.fetchAll(From<Event>())
            return (walks, events)
        }) { result in
            switch result {
            case .success(let (transactionWalks, transactionEvents)):
                let walks = DataManager.dataStack.fetchExisting(transactionWalks)
                let events = DataManager.dataStack.fetchExisting(transactionEvents)
                guard !walks.isEmpty else {
                    completion(.failure(.noWalksFound))
                    return
                }

                let pilgrimWalks = walks.compactMap {
                    PilgrimPackageConverter.convert(
                        walk: $0,
                        system: system,
                        celestialEnabled: celestialEnabled,
                        includePhotos: includePhotos
                    )
                }
                let pilgrimEvents = PilgrimPackageConverter.convertEvents(events: events)
                let manifest = PilgrimPackageConverter.buildManifest(
                    walkCount: pilgrimWalks.count,
                    events: pilgrimEvents
                )

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try assemblePackage(
                            walks: pilgrimWalks,
                            manifest: manifest,
                            embedPhotos: includePhotos
                        )
                        completion(.success(result))
                    } catch let error as PilgrimPackageError {
                        completion(.failure(error))
                    } catch {
                        completion(.failure(.fileSystemError(error)))
                    }
                }
            case .failure:
                completion(.failure(.noWalksFound))
            }
        }
    }

    private static func assemblePackage(
        walks: [PilgrimWalk],
        manifest: PilgrimManifest,
        embedPhotos: Bool
    ) throws -> PilgrimPackageBuildResult {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-export-\(UUID().uuidString)")
        let walksDir = tempDir.appendingPathComponent("walks")

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: walksDir, withIntermediateDirectories: true)

        // Embed photo bytes BEFORE encoding walks to JSON so each walk's
        // photos[] array can carry the final embeddedPhotoFilename. Photos
        // without a filename after embedding are dropped from the JSON
        // (the viewer would have no bytes to point at) and counted as
        // skipped for the result.
        let embedResult: PilgrimPhotoEmbedder.EmbedResult
        let finalWalks: [PilgrimWalk]
        if embedPhotos {
            embedResult = PilgrimPhotoEmbedder.embedPhotos(from: walks, into: tempDir)
            finalWalks = walks.map { walk in
                applyEmbeddedFilenames(to: walk, using: embedResult.filenameMap)
            }
        } else {
            embedResult = .init(filenameMap: [:], skippedCount: 0)
            finalWalks = walks
        }

        let encoder = PilgrimDateCoding.makeEncoder()

        for walk in finalWalks {
            let walkData = try encoder.encode(walk)
            let walkFile = walksDir.appendingPathComponent("\(walk.id.uuidString).json")
            try walkData.write(to: walkFile)
        }

        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))

        let schemaData = Data(PilgrimPackageSchema.json.utf8)
        try schemaData.write(to: tempDir.appendingPathComponent("schema.json"))

        let timeCode = CustomDateFormatting.backupTimeCode(forDate: Date())
        let archiveURL = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-\(timeCode).pilgrim")

        try? fm.removeItem(at: archiveURL)
        try fm.zipItem(at: tempDir, to: archiveURL, shouldKeepParent: false)

        return PilgrimPackageBuildResult(
            url: archiveURL,
            skippedPhotoCount: embedResult.skippedCount
        )
    }

    /// Returns a copy of the walk with each photo's `embeddedPhotoFilename`
    /// populated from the map. Photos whose `localIdentifier` isn't in the
    /// map (embedding failed) are dropped — the viewer has no bytes to
    /// render them, and carrying orphan metadata would give false
    /// expectation that the photo is in the archive.
    ///
    /// Internal (not private) so `PilgrimPhotoEmbedderTests` can exercise
    /// the drop-and-stamp logic directly without needing a live PhotoKit
    /// round-trip.
    static func applyEmbeddedFilenames(
        to walk: PilgrimWalk,
        using filenameMap: [String: String]
    ) -> PilgrimWalk {
        guard let photos = walk.photos else { return walk }
        var updated = walk
        updated.photos = photos.compactMap { photo in
            guard let filename = filenameMap[photo.localIdentifier] else {
                return nil
            }
            return PilgrimPhoto(
                localIdentifier: photo.localIdentifier,
                capturedAt: photo.capturedAt,
                capturedLat: photo.capturedLat,
                capturedLng: photo.capturedLng,
                keptAt: photo.keptAt,
                embeddedPhotoFilename: filename
            )
        }
        return updated
    }
}

// MARK: - JSON Schema

enum PilgrimPackageSchema {

    static let json = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "Pilgrim Walk Export",
      "description": "Schema for .pilgrim walk data files. Dates are seconds since 1970-01-01T00:00:00Z. Coordinates are [longitude, latitude, altitude].",
      "type": "object",
      "properties": {
        "schemaVersion": { "type": "string", "const": "1.0" },
        "id": { "type": "string", "format": "uuid" },
        "type": { "type": "string", "enum": ["walking", "unknown"] },
        "startDate": { "type": "number", "description": "seconds since epoch" },
        "endDate": { "type": "number", "description": "seconds since epoch" },
        "stats": {
          "type": "object",
          "properties": {
            "distance": { "type": "number", "description": "meters" },
            "steps": { "type": ["integer", "null"] },
            "activeDuration": { "type": "number", "description": "seconds" },
            "pauseDuration": { "type": "number", "description": "seconds" },
            "ascent": { "type": "number", "description": "meters" },
            "descent": { "type": "number", "description": "meters" },
            "burnedEnergy": { "type": ["number", "null"], "description": "kcal" },
            "talkDuration": { "type": "number", "description": "seconds" },
            "meditateDuration": { "type": "number", "description": "seconds" }
          },
          "required": ["distance", "activeDuration", "pauseDuration", "ascent", "descent", "talkDuration", "meditateDuration"]
        },
        "weather": { "type": ["object", "null"] },
        "route": {
          "type": "object",
          "description": "GeoJSON FeatureCollection. Coordinates are [longitude, latitude, altitude]."
        },
        "pauses": { "type": "array" },
        "activities": { "type": "array" },
        "voiceRecordings": { "type": "array" },
        "heartRates": { "type": "array" },
        "workoutEvents": { "type": "array" },
        "photos": {
          "type": ["array", "null"],
          "description": "Reliquary photos the user opted to include at export time. Each entry carries its PHAsset localIdentifier, GPS coordinates, captured/kept timestamps, and an optional embeddedPhotoFilename pointing at a file under the archive's photos/ directory. Absent entirely when the user opts out — older files and opted-out exports stay byte-identical."
        },
        "intention": { "type": ["string", "null"] },
        "reflection": { "type": ["object", "null"] },
        "favicon": { "type": ["string", "null"] },
        "isRace": { "type": "boolean" },
        "isUserModified": { "type": "boolean" },
        "finishedRecording": { "type": "boolean" }
      },
      "required": ["schemaVersion", "id", "type", "startDate", "endDate", "stats", "route", "pauses", "activities", "voiceRecordings", "heartRates", "workoutEvents"]
    }
    """
}
