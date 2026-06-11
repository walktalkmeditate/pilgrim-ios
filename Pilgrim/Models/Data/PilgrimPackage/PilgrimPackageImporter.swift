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
/// What an import actually did. `added` walks are net-new on this
/// device. `replaced` walks were already present and got overwritten
/// with the tended version (only happens for tended files —
/// `manifest.modifications[]` non-empty or `manifest.archived[]`
/// non-empty). `archived` walks transitioned to the archived state.
/// `skipped` counts walk files that could not be decoded (corrupt or
/// truncated JSON) and `failedEvents` counts journeys whose save
/// transaction failed — both are surfaced so a partial import is never
/// reported as unqualified success.
struct ImportSummary: Equatable {
    let added: Int
    let replaced: Int
    let archived: Int
    let skipped: Int
    let failedEvents: Int

    static let empty = ImportSummary(added: 0, replaced: 0, archived: 0, skipped: 0, failedEvents: 0)

    var totalChanges: Int { added + replaced + archived }
    var hasFailures: Bool { skipped > 0 || failedEvents > 0 }
}

/// Decoded contents of a `.pilgrim` archive, pre-database.
struct DecodedPackage {
    let walks: [TempWalk]
    let events: [TempEvent]
    let archived: [PilgrimArchivedWalk]
    let isTended: Bool
    let skippedWalks: Int
}

enum PilgrimPackageImporter {

    static func importPackage(
        from url: URL,
        completion: @escaping (Result<ImportSummary, PilgrimPackageError>) -> Void
    ) {
        let completion = safeClosure(from: completion)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let package = try unpackAndDecode(from: url)
                DispatchQueue.main.async {
                    saveData(package: package, completion: completion)
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
    static func unpackAndDecode(from url: URL) throws -> DecodedPackage {
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

        let (tempWalks, skippedWalks) = try decodeWalks(in: walksDir, decoder: decoder)

        let tempEvents = PilgrimPackageConverter.convertEvents(manifest.events)

        return DecodedPackage(
            walks: tempWalks,
            events: tempEvents,
            archived: manifest.archivedOrEmpty,
            isTended: manifest.isTended,
            skippedWalks: skippedWalks
        )
    }

    /// Decodes every `walks/*.json` file, counting undecodable files as
    /// skipped (AF28) instead of dropping them silently. Throws only when
    /// walk files exist but none decode — that's a broken archive, not a
    /// partial one.
    private static func decodeWalks(
        in walksDir: URL,
        decoder: JSONDecoder
    ) throws -> (walks: [TempWalk], skipped: Int) {
        let walkFiles = try FileManager.default.contentsOfDirectory(
            at: walksDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var tempWalks: [TempWalk] = []
        var skippedWalks = 0
        for fileURL in walkFiles {
            let data = try Data(contentsOf: fileURL)
            let pilgrimWalk: PilgrimWalk
            do {
                pilgrimWalk = try decoder.decode(PilgrimWalk.self, from: data)
            } catch {
                print("[PilgrimPackageImporter] Skipping \(fileURL.lastPathComponent): \(error)")
                skippedWalks += 1
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

        return (tempWalks, skippedWalks)
    }

    private static func saveData(
        package: DecodedPackage,
        completion: @escaping (Result<ImportSummary, PilgrimPackageError>) -> Void
    ) {
        let events = package.events
        let archived = package.archived
        let skippedWalks = package.skippedWalks

        let filteredWalks = filterLocallyArchived(package.walks)

        if filteredWalks.isEmpty && archived.isEmpty {
            completion(.success(ImportSummary(
                added: 0, replaced: 0, archived: 0,
                skipped: skippedWalks, failedEvents: 0
            )))
            return
        }

        let archivedCount = archived.count

        if filteredWalks.isEmpty {
            applyArchivedOnly(archived, skippedWalks: skippedWalks, completion: completion)
            return
        }

        // Tended files (manifest.modifications[] or manifest.archived[]
        // non-empty) carry the user's edits applied via the web editor.
        // The per-walk JSON payloads ALREADY reflect the post-edit state,
        // so we overwrite by UUID — DataManager.replaceWalks deletes the
        // existing CoreStore row and inserts the tended version in ONE
        // transaction, so a failure mid-import rolls back and the user's
        // originals survive untouched. Fresh exports stay
        // append-only-by-UUID so the cross-device merge use case (drop two
        // .pilgrim files in succession) keeps working.
        let handleSaveResult: (Bool, DataManager.SaveMultipleError?, [Walk], Int, [UUID: [String]]) -> Void = { success, error, savedWalks, replacedCount, capturedPaths in
            if success {
                let addedCount = max(0, savedWalks.count - replacedCount)
                saveImportedEvents(events) { failedEvents in
                    restoreCapturedRecordingPaths(capturedPaths) {
                        applyArchivedEntries(archived, dataStack: DataManager.dataStack) { result in
                            if case .failure(let err) = result {
                                print("[PilgrimPackageImporter] Archive apply failed: \(err)")
                            }
                            completion(.success(ImportSummary(
                                added: addedCount,
                                replaced: replacedCount,
                                archived: archivedCount,
                                skipped: skippedWalks,
                                failedEvents: failedEvents
                            )))
                        }
                    }
                }
            } else if let error = error {
                completion(.failure(.fileSystemError(
                    NSError(domain: "PilgrimPackageImporter",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "\(error)"])
                )))
            } else {
                completion(.success(ImportSummary(
                    added: savedWalks.count,
                    replaced: replacedCount,
                    archived: archivedCount,
                    skipped: skippedWalks,
                    failedEvents: 0
                )))
            }
        }

        if package.isTended {
            DataManager.replaceWalks(objects: filteredWalks, dataStack: DataManager.dataStack) { success, error, savedWalks, replacedCount, capturedPaths in
                handleSaveResult(success, error, savedWalks, replacedCount, capturedPaths)
            }
        } else {
            DataManager.saveWalks(objects: filteredWalks) { success, error, savedWalks in
                handleSaveResult(success, error, savedWalks, 0, [:])
            }
        }
    }

    /// Walks already archived on this device are deliberately not
    /// re-imported — the archive registry is the local source of truth.
    private static func filterLocallyArchived(_ walks: [TempWalk]) -> [TempWalk] {
        let localRegistry = UserPreferences.archivedWalkRegistry.value
        return walks.filter { walk in
            guard let uuid = walk.uuid else { return true }
            if localRegistry[uuid.uuidString] != nil {
                print("[PilgrimPackageImporter] Skipping walk \(uuid) — already archived locally")
                return false
            }
            return true
        }
    }

    private static func applyArchivedOnly(
        _ archived: [PilgrimArchivedWalk],
        skippedWalks: Int,
        completion: @escaping (Result<ImportSummary, PilgrimPackageError>) -> Void
    ) {
        applyArchivedEntries(archived, dataStack: DataManager.dataStack) { result in
            switch result {
            case .success:
                completion(.success(ImportSummary(
                    added: 0, replaced: 0, archived: archived.count,
                    skipped: skippedWalks, failedEvents: 0
                )))
            case .failure(let error):
                completion(.failure(.fileSystemError(error)))
            }
        }
    }

    /// Saves the manifest's events (journeys), reporting how many failed
    /// (AF76) — the walks are already committed at this point, so an event
    /// failure degrades the summary instead of failing the import.
    private static func saveImportedEvents(
        _ events: [TempEvent],
        completion: @escaping (_ failedEvents: Int) -> Void
    ) {
        guard !events.isEmpty else {
            completion(0)
            return
        }
        DataManager.saveEvents(objects: events) { saved, error, _ in
            if !saved {
                print("[PilgrimPackageImporter] Event save failed: \(String(describing: error))")
            }
            completion(saved ? 0 : events.count)
        }
    }

    /// Re-attaches captured `fileRelativePath` values to the voice-recording
    /// rows that `saveWalks` just inserted. Matches by walk UUID + recording
    /// startDate ordinal — the order is stable across export/import because
    /// PilgrimPackageConverter preserves `voiceRecordings` order, and we
    /// captured the paths in the same startDate order pre-delete.
    private static func restoreCapturedRecordingPaths(
        _ paths: [UUID: [String]],
        completion: @escaping () -> Void
    ) {
        guard !paths.isEmpty else {
            completion()
            return
        }

        DataManager.dataStack.perform(asynchronous: { transaction in
            for (walkUUID, recordingPaths) in paths {
                guard let walk = try transaction.fetchOne(
                    From<Walk>().where(\Walk._uuid == walkUUID)
                ) else { continue }
                guard let editableWalk = transaction.edit(walk) else { continue }

                let recordings = editableWalk._voiceRecordings.value
                    .sorted { $0._startDate.value < $1._startDate.value }

                // Count guard: if the editor added or removed recordings (the
                // .pilgrim format does not currently support this, but a
                // future format might), the startDate-ordinal match would
                // assign paths to the wrong recordings. Skip restore for
                // this walk and log — accepting empty paths is safer than
                // silently corrupting the audio mapping.
                guard recordings.count == recordingPaths.count else {
                    print("[PilgrimPackageImporter] Skipping path restore for walk \(walkUUID.uuidString.prefix(8)) — count mismatch (\(recordings.count) recordings vs \(recordingPaths.count) captured paths)")
                    continue
                }

                for (idx, recording) in recordings.enumerated() {
                    let path = recordingPaths[idx]
                    guard !path.isEmpty else { continue }
                    if let editableRec = transaction.edit(recording) {
                        editableRec._fileRelativePath .= path
                    }
                }
            }
        }) { result in
            if case .failure(let error) = result {
                print("[PilgrimPackageImporter] Recording-path restore failed: \(error)")
            }
            completion()
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
