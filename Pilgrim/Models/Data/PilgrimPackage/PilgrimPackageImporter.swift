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
struct ImportSummary: Equatable {
    let added: Int
    let replaced: Int
    let archived: Int

    static let empty = ImportSummary(added: 0, replaced: 0, archived: 0)

    var totalChanges: Int { added + replaced + archived }
}

enum PilgrimPackageImporter {

    static func importPackage(
        from url: URL,
        completion: @escaping (Result<ImportSummary, PilgrimPackageError>) -> Void
    ) {
        let completion = safeClosure(from: completion)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (walks, events, archived, isTended) = try unpackAndDecode(from: url)
                DispatchQueue.main.async {
                    saveData(
                        walks: walks,
                        events: events,
                        archived: archived,
                        isTended: isTended,
                        completion: completion
                    )
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
    static func unpackAndDecode(from url: URL) throws -> ([TempWalk], [TempEvent], [PilgrimArchivedWalk], Bool) {
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

        return (tempWalks, tempEvents, manifest.archivedOrEmpty, manifest.isTended)
    }

    private static func saveData(
        walks: [TempWalk],
        events: [TempEvent],
        archived: [PilgrimArchivedWalk],
        isTended: Bool,
        completion: @escaping (Result<ImportSummary, PilgrimPackageError>) -> Void
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
            completion(.success(.empty))
            return
        }

        let archivedCount = archived.count

        if filteredWalks.isEmpty {
            applyArchivedEntries(archived, dataStack: DataManager.dataStack) { result in
                switch result {
                case .success:
                    completion(.success(ImportSummary(added: 0, replaced: 0, archived: archivedCount)))
                case .failure(let error):
                    completion(.failure(.fileSystemError(error)))
                }
            }
            return
        }

        // Tended files (manifest.modifications[] or manifest.archived[]
        // non-empty) carry the user's edits applied via the web editor.
        // The per-walk JSON payloads ALREADY reflect the post-edit state,
        // so we overwrite by UUID — delete the existing CoreStore row
        // and let saveWalks insert the tended version. Fresh exports
        // stay append-only-by-UUID so the cross-device merge use case
        // (drop two .pilgrim files in succession) keeps working.
        let preflight: (@escaping (Int, [UUID: [String]]) -> Void) -> Void = { next in
            guard isTended else {
                next(0, [:])
                return
            }
            deleteExistingWalksMatching(filteredWalks) { replacedCount, capturedPaths in
                next(replacedCount, capturedPaths)
            }
        }

        preflight { replacedCount, capturedPaths in
            DataManager.saveWalks(objects: filteredWalks) { success, error, savedWalks in
                if success {
                    let totalSaved = savedWalks.count
                    let addedCount = max(0, totalSaved - replacedCount)

                    let saveEventsAndApplyArchived = {
                        restoreCapturedRecordingPaths(capturedPaths) {
                            applyArchivedEntries(archived, dataStack: DataManager.dataStack) { result in
                                if case .failure(let err) = result {
                                    print("[PilgrimPackageImporter] Archive apply failed: \(err)")
                                }
                                completion(.success(ImportSummary(
                                    added: addedCount,
                                    replaced: replacedCount,
                                    archived: archivedCount
                                )))
                            }
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
                    completion(.success(ImportSummary(
                        added: savedWalks.count,
                        replaced: replacedCount,
                        archived: archivedCount
                    )))
                }
            }
        }
    }

    /// For each walk in `incoming` whose UUID matches an existing
    /// CoreStore Walk, deletes the existing row in a single transaction.
    /// Captures each walk's voice-recording fileRelativePaths (in startDate
    /// order) before deletion so they can be restored after `saveWalks`
    /// re-inserts the walk — the `.pilgrim` format does not carry per-
    /// recording paths, and without this round-trip the re-inserted
    /// recordings end up with empty paths (= "unavailable" in UI, audio
    /// files become orphans on next sweep). Calls back on the main queue
    /// with `(deletedCount, [walkUUID: [recordingPath]])`.
    private static func deleteExistingWalksMatching(
        _ incoming: [TempWalk],
        completion: @escaping (Int, [UUID: [String]]) -> Void
    ) {
        let incomingUUIDs = Set(incoming.compactMap { $0.uuid })
        guard !incomingUUIDs.isEmpty else {
            completion(0, [:])
            return
        }

        DataManager.dataStack.perform(asynchronous: { transaction -> (Int, [UUID: [String]]) in
            var deleted = 0
            var capturedPaths: [UUID: [String]] = [:]
            for uuid in incomingUUIDs {
                let existing = try transaction.fetchAll(
                    From<Walk>().where(\Walk._uuid == uuid)
                )
                for walk in existing {
                    let paths = walk._voiceRecordings.value
                        .sorted { $0._startDate.value < $1._startDate.value }
                        .map { $0._fileRelativePath.value }
                    if !paths.isEmpty {
                        capturedPaths[uuid] = paths
                    }
                    transaction.delete(walk)
                    deleted += 1
                }
            }
            return (deleted, capturedPaths)
        }) { result in
            switch result {
            case .success(let (count, paths)):
                completion(count, paths)
            case .failure(let error):
                print("[PilgrimPackageImporter] Tended-overwrite delete failed: \(error)")
                completion(0, [:])
            }
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
                for (idx, recording) in recordings.enumerated() {
                    guard idx < recordingPaths.count else { break }
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
