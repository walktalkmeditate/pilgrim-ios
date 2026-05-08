import Foundation
import CoreStore
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
                let (walks, events, archived) = try unpackAndDecode(from: url)
                DispatchQueue.main.async {
                    saveData(walks: walks, events: events, archived: archived, completion: completion)
                }
            } catch let error as PilgrimPackageError {
                completion(.failure(error))
            } catch {
                completion(.failure(.fileSystemError(error)))
            }
        }
    }

    /// Unzips the archive at `url` and decodes the walks + events + archived
    /// entries from its JSON payload. Internal (not private) so unit tests can
    /// exercise the parse pipeline against a fixture archive without going
    /// through `DataManager.saveWalks` (which requires a live CoreStore stack).
    static func unpackAndDecode(from url: URL) throws -> ([TempWalk], [TempEvent], [PilgrimArchivedWalk]) {
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

        return (tempWalks, tempEvents, manifest.archivedOrEmpty)
    }

    private static func saveData(
        walks: [TempWalk],
        events: [TempEvent],
        archived: [PilgrimArchivedWalk],
        completion: @escaping (Result<Int, PilgrimPackageError>) -> Void
    ) {
        let localRegistry = UserPreferences.archivedWalkRegistry.value

        let filteredWalks = walks.filter { walk in
            guard let uuid = walk.uuid else { return true }
            if localRegistry[uuid.uuidString] != nil {
                print("[PilgrimPackageImporter] Skipping walk \(uuid) — already archived locally")
                return false
            }
            return true
        }

        if filteredWalks.isEmpty && archived.isEmpty {
            completion(.success(0))
            return
        }

        if filteredWalks.isEmpty {
            applyArchivedEntries(archived, dataStack: DataManager.dataStack) { result in
                switch result {
                case .success:
                    completion(.success(0))
                case .failure(let error):
                    completion(.failure(.fileSystemError(error)))
                }
            }
            return
        }

        DataManager.saveWalks(objects: filteredWalks) { success, error, savedWalks in
            if success {
                let savedCount = savedWalks.count

                let saveEventsAndApplyArchived = {
                    applyArchivedEntries(archived, dataStack: DataManager.dataStack) { result in
                        if case .failure(let err) = result {
                            print("[PilgrimPackageImporter] Archive apply failed: \(err)")
                        }
                        completion(.success(savedCount))
                    }
                }

                if !events.isEmpty {
                    DataManager.saveEvents(objects: events) { _, _, _ in
                        saveEventsAndApplyArchived()
                    }
                } else {
                    saveEventsAndApplyArchived()
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

    /// Applies archived walk entries from a `.pilgrim` manifest into CoreStore.
    ///
    /// For each entry:
    /// - If a Walk with the same UUID exists, strips its heavy data (route,
    ///   photos, recordings, heart rates, waypoints, pauses, events,
    ///   activity intervals, weather, comment, favicon). Surface stats
    ///   (distance, durations, steps) are left unchanged.
    /// - If no Walk exists, creates a stub with the archived stats and dates.
    ///
    /// In both cases, the UUID is registered post-commit via
    /// `UserPreferences.markWalkArchived`. Audio files captured before the
    /// transaction commits are deleted post-commit.
    ///
    /// Internal (not private) so tests can call it with an in-memory DataStack.
    static func applyArchivedEntries(
        _ archived: [PilgrimArchivedWalk],
        dataStack: DataStack,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !archived.isEmpty else {
            completion(.success(()))
            return
        }

        dataStack.perform(asynchronous: { transaction -> ([URL], [(UUID, Date)]) in

            var capturedFileURLs: [URL] = []
            var archivedMap: [(UUID, Date)] = []
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

            for payload in archived {
                let uuid = payload.id
                let archivedAt = Date(timeIntervalSince1970: payload.archivedAt)

                if let walk = try? transaction.fetchOne(From<Walk>().where(\._uuid == uuid)),
                   let editableWalk = transaction.edit(walk) {
                    capturedFileURLs += stripHeavyData(from: editableWalk, docs: docs, in: transaction)
                } else {
                    createStubWalk(for: payload, in: transaction)
                }

                archivedMap.append((uuid, archivedAt))
            }

            return (capturedFileURLs, archivedMap)

        }) { result in
            switch result {
            case .success(let (fileURLs, archivedMap)):
                for (uuid, archivedAt) in archivedMap {
                    UserPreferences.markWalkArchived(uuid: uuid, archivedAt: archivedAt)
                }
                for url in fileURLs {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        print("[ArchiveImport] Could not remove \(url.lastPathComponent): \(error)")
                    }
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func stripHeavyData(
        from walk: Walk,
        docs: URL,
        in transaction: AsynchronousDataTransaction
    ) -> [URL] {
        var fileURLs: [URL] = []
        let recordings = walk._voiceRecordings.value
        for recording in recordings {
            let path = recording._fileRelativePath.value
            if !path.isEmpty {
                fileURLs.append(docs.appendingPathComponent(path))
            }
        }

        for rec in recordings { transaction.delete(rec) }
        for sample in walk._routeData.value { transaction.delete(sample) }
        for photo in walk._walkPhotos.value { transaction.delete(photo) }
        for rate in walk._heartRates.value { transaction.delete(rate) }
        for waypoint in walk._waypoints.value { transaction.delete(waypoint) }
        for pause in walk._pauses.value { transaction.delete(pause) }
        for event in walk._workoutEvents.value { transaction.delete(event) }
        for interval in walk._activityIntervals.value { transaction.delete(interval) }

        walk._comment .= nil
        walk._favicon .= nil
        walk._weatherCondition .= nil
        walk._weatherTemperature .= nil
        walk._weatherHumidity .= nil
        walk._weatherWindSpeed .= nil

        return fileURLs
    }

    private static func createStubWalk(
        for payload: PilgrimArchivedWalk,
        in transaction: AsynchronousDataTransaction
    ) {
        let startDate = Date(timeIntervalSince1970: payload.startDate)
        let stub = transaction.create(Into<Walk>())
        stub._uuid .= payload.id
        stub._workoutType .= .walking
        stub._startDate .= startDate
        stub._endDate .= Date(timeIntervalSince1970: payload.endDate)
        stub._distance .= payload.stats.distance
        stub._activeDuration .= payload.stats.activeDuration
        stub._pauseDuration .= 0
        stub._talkDuration .= payload.stats.talkDuration
        stub._meditateDuration .= payload.stats.meditateDuration
        stub._steps .= payload.stats.steps
        stub._ascend .= 0
        stub._descend .= 0
        stub._isUserModified .= true
        stub._isRace .= false
        stub._finishedRecording .= true
        stub._dayIdentifier .= CustomDateFormatting.dayIdentifier(forDate: startDate)
        stub._healthKitUUID .= nil
    }
}
