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

enum PilgrimPackageBuilder {

    /// Build a `.pilgrim` archive.
    ///
    /// - parameter includePhotos: When true, the user's pinned reliquary
    ///   photos are included in each walk's JSON (and in Stage 5c, their
    ///   bytes are resized and written into the archive's `photos/`
    ///   directory). Defaults to `false` so any caller that hasn't gone
    ///   through the export confirmation sheet produces a photo-free
    ///   archive — this defends against a future regression where someone
    ///   adds a new call site and forgets about consent.
    static func build(
        includePhotos: Bool = false,
        completion: @escaping (Result<URL, PilgrimPackageError>) -> Void
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
                        let url = try assemblePackage(
                            walks: pilgrimWalks,
                            manifest: manifest
                        )
                        completion(.success(url))
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
        manifest: PilgrimManifest
    ) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-export-\(UUID().uuidString)")
        let walksDir = tempDir.appendingPathComponent("walks")

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: walksDir, withIntermediateDirectories: true)

        let encoder = PilgrimDateCoding.makeEncoder()

        for walk in walks {
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

        return archiveURL
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
