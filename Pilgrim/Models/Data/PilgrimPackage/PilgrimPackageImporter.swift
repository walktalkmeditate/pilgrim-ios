import Foundation
import ZIPFoundation

/// Reads a `.pilgrim` archive back into the app's database.
///
/// **Stage 5 photo handling**: archives produced by Stage 5+ may contain
/// a top-level `photos/` directory carrying resized JPEG bytes for the
/// user's pinned reliquary photos. The importer **silently tolerates**
/// this directory:
///
/// - The unzip step extracts every file (including `photos/<x>.jpg`) into
///   the per-import tempDir, but the importer **never reads or copies**
///   the photo bytes into app storage. Photos are viewer-only by design.
/// - Each walk's JSON `photos[]` array is decoded into `PilgrimPhoto`
///   structs via the standard `Codable` path (Stage 5a's optional field).
/// - `PilgrimPackageConverter.convertToTemp` calls
///   `PilgrimPackagePhotoConverter.importPhotos` to map those into
///   `TempWalkPhoto` entities — dropping `embeddedPhotoFilename` because
///   the app side has no field for it. The persisted `WalkPhoto` rows
///   carry only `localIdentifier + GPS + timestamps`.
/// - The tempDir (including the `photos/` subdirectory) is removed via
///   `defer` when `unpackAndDecode` returns. No photo bytes survive.
///
/// Result: on the receiving device, the imported walk has a populated
/// reliquary IF the user's iCloud Photos library still resolves the
/// localIdentifiers — which works for AirDrop between two devices on the
/// same iCloud account. For everyone else, the metadata is preserved but
/// the photos won't render in-app (they only render in the desktop viewer
/// where the embedded JPEG bytes are read directly from the archive).
enum PilgrimPackageImporter {

    static func importPackage(
        from url: URL,
        completion: @escaping (Result<Int, PilgrimPackageError>) -> Void
    ) {
        let completion = safeClosure(from: completion)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (walks, events) = try unpackAndDecode(from: url)
                DispatchQueue.main.async {
                    saveData(walks: walks, events: events, completion: completion)
                }
            } catch let error as PilgrimPackageError {
                completion(.failure(error))
            } catch {
                completion(.failure(.fileSystemError(error)))
            }
        }
    }

    /// Unzips the archive at `url` and decodes the walks + events from
    /// its JSON payload. Internal (not private) so unit tests can
    /// exercise the parse pipeline against a fixture archive without
    /// going through `DataManager.saveWalks` (which requires a live
    /// CoreStore stack).
    static func unpackAndDecode(from url: URL) throws -> ([TempWalk], [TempEvent]) {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-import-\(UUID().uuidString)")

        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fm.unzipItem(at: url, to: tempDir)
        } catch {
            throw PilgrimPackageError.zipFailed(error)
        }

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw PilgrimPackageError.invalidPackage
        }

        let decoder = PilgrimDateCoding.makeDecoder()

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: PilgrimManifest
        do {
            manifest = try decoder.decode(PilgrimManifest.self, from: manifestData)
        } catch {
            throw PilgrimPackageError.decodingFailed(error)
        }

        guard manifest.schemaVersion == "1.0" else {
            throw PilgrimPackageError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        let walksDir = tempDir.appendingPathComponent("walks")
        guard fm.fileExists(atPath: walksDir.path) else {
            throw PilgrimPackageError.invalidPackage
        }

        let walkFiles = try fm.contentsOfDirectory(
            at: walksDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var tempWalks: [TempWalk] = []
        for fileURL in walkFiles {
            let data = try Data(contentsOf: fileURL)
            let pilgrimWalk: PilgrimWalk
            do {
                pilgrimWalk = try decoder.decode(PilgrimWalk.self, from: data)
            } catch {
                print("[PilgrimPackageImporter] Skipping \(fileURL.lastPathComponent): \(error)")
                continue
            }
            tempWalks.append(PilgrimPackageConverter.convertToTemp(walk: pilgrimWalk))
        }

        if !walkFiles.isEmpty && tempWalks.isEmpty {
            throw PilgrimPackageError.decodingFailed(
                NSError(domain: "PilgrimPackageImporter", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No walks could be decoded"])
            )
        }

        let tempEvents = PilgrimPackageConverter.convertEvents(manifest.events)

        return (tempWalks, tempEvents)
    }

    private static func saveData(
        walks: [TempWalk],
        events: [TempEvent],
        completion: @escaping (Result<Int, PilgrimPackageError>) -> Void
    ) {
        guard !walks.isEmpty else {
            completion(.success(0))
            return
        }

        DataManager.saveWalks(objects: walks) { success, error, savedWalks in
            if success {
                if !events.isEmpty {
                    DataManager.saveEvents(objects: events) { _, _, _ in
                        completion(.success(savedWalks.count))
                    }
                } else {
                    completion(.success(savedWalks.count))
                }
            } else if let error = error {
                completion(.failure(.fileSystemError(
                    NSError(domain: "PilgrimPackageImporter",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "\(error)"])
                )))
            } else {
                completion(.success(savedWalks.count))
            }
        }
    }
}
