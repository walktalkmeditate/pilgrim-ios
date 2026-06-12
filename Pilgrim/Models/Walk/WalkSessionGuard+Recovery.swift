import Foundation
import AVFoundation

/// Crash recovery: decodes the checkpoint a SIGKILL'd walk left behind,
/// reconnects orphaned audio, and saves the walk back into the store.
extension WalkSessionGuard {

    /// The `WalkCheckpoint.schemaVersion` value this build can decode and recover.
    /// Tracks the writer's current version directly — bumping `WalkCheckpoint.currentSchemaVersion`
    /// automatically narrows the set of checkpoints older builds will accept.
    private static let supportedSchemaVersion = WalkCheckpoint.currentSchemaVersion

    /// Replaces a recording's file path with `""` (metadata-only) when the
    /// underlying `.m4a` is unplayable — the canonical signature of an
    /// AVAudioRecorder that was SIGKILL'd before `stop()` wrote its moov atom.
    /// Duration is preserved so the Talk timer still reads correctly after
    /// recovery; the walk summary row will show "Recording unavailable" and
    /// suppress playback controls.
    ///
    /// Parameters:
    /// - recording: the provisional recording from the checkpoint
    /// - fileURL: absolute URL of the on-disk file. Pass `nil` to skip the
    ///   disk check entirely (used in tests with the `durationProbe` param).
    /// - durationProbe: returns the playable duration for a file. In
    ///   production, defaults to `AVURLAsset(url:).duration` seconds.
    ///   Override in tests to avoid AVFoundation dependencies.
    static func sanitizeRecording(
        _ recording: TempVoiceRecording,
        fileURL: URL?,
        durationProbe: (URL) -> Double = WalkSessionGuard.defaultDurationProbe
    ) -> TempVoiceRecording {
        guard let fileURL else { return recording }

        let playableSeconds = durationProbe(fileURL)
        guard playableSeconds <= 0 else {
            return recording
        }

        try? FileManager.default.removeItem(at: fileURL)

        return TempVoiceRecording(
            uuid: recording.uuid,
            startDate: recording.startDate,
            endDate: recording.endDate,
            duration: recording.duration,
            fileRelativePath: "",
            transcription: nil,
            wordsPerMinute: nil,
            isEnhanced: false
        )
    }

    private static func defaultDurationProbe(_ url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite ? seconds : 0
    }

    /// `sweepGate` is resolved on every path that leaves no checkpoint
    /// blocking the orphan sweep (no file, file deleted, or recovery
    /// committed). It is deliberately NOT resolved when the recovery save
    /// fails and the checkpoint is kept — sweeping then would delete the
    /// crashed walk's audio files before their DB rows exist (AF2).
    static func recoverIfNeeded(
        sweepGate: OrphanSweepGate = .shared,
        completion: @escaping (Date?) -> Void
    ) {
        guard DataManager.dataStack != nil else {
            print("\(tag) RECOVERY SKIPPED — DataManager not ready")
            completion(nil)
            return
        }

        let url = checkpointFileURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("\(tag) RECOVERY — no checkpoint file found")
            sweepGate.noteWalkRecoveryResolved()
            completion(nil)
            return
        }

        print("\(tag) RECOVERY — checkpoint file found, decoding...")

        guard let checkpoint = decodeRecoverableCheckpoint(at: url) else {
            sweepGate.noteWalkRecoveryResolved()
            completion(nil)
            return
        }

        let walk = checkpoint.walk
        let recordingDirUUID = extractRecordingDirectoryUUID(from: walk) ?? checkpoint.walkUUID
        reconnectOrphanedRecordings(walk: walk, walkUUID: recordingDirUUID)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sanitized = walk._voiceRecordings.map { recording -> TempVoiceRecording in
            guard isProvisional(recording), !recording.fileRelativePath.isEmpty else {
                return recording
            }
            let url = docs.appendingPathComponent(recording.fileRelativePath)
            return sanitizeRecording(recording, fileURL: url)
        }
        walk.replaceVoiceRecordings(sanitized)

        print("\(tag) RECOVERY — saving walk: start=\(walk.startDate), end=\(walk.endDate), routes=\(walk.routeData.count), pauses=\(walk.pauses.count), recordings=\(walk.voiceRecordings.count), intervals=\(walk.activityIntervals.count), waypoints=\(walk.waypoints.count)")

        let recovered = makeRecoveredWalk(from: checkpoint)

        DataManager.saveWalk(object: recovered) { success, error, _ in
            if success {
                try? FileManager.default.removeItem(at: url)
                print("\(tag) RECOVERY SUCCESS — walk from \(walk.startDate) saved, checkpoint deleted")
                sweepGate.noteWalkRecoveryResolved()
                completion(walk.startDate)
            } else {
                print("\(tag) RECOVERY SAVE FAILED: \(String(describing: error)), keeping checkpoint for retry")
                completion(nil)
            }
        }
    }

    /// Decodes and validates the checkpoint at `url`. Returns nil — after
    /// deleting the file — when it is undecodable, from an unsupported
    /// schema version, or stale (its walk is already in the database).
    private static func decodeRecoverableCheckpoint(at url: URL) -> WalkCheckpoint? {
        let checkpoint: WalkCheckpoint
        do {
            let data = try Data(contentsOf: url)
            checkpoint = try JSONDecoder().decode(WalkCheckpoint.self, from: data)
            print("\(tag) RECOVERY — decoded: schema=\(checkpoint.schemaVersion), walkUUID=\(checkpoint.walkUUID.uuidString.prefix(8))..., checkpointDate=\(checkpoint.checkpointDate)")
        } catch {
            print("\(tag) RECOVERY FAILED — decode error: \(error)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        guard checkpoint.schemaVersion == Self.supportedSchemaVersion else {
            print("\(tag) RECOVERY FAILED — unsupported schemaVersion: \(checkpoint.schemaVersion) (this build supports \(Self.supportedSchemaVersion))")
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        if DataManager.objectHasDuplicate(uuid: checkpoint.walkUUID, objectType: Walk.self) {
            print("\(tag) RECOVERY — stale checkpoint (walk already saved), deleting")
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return checkpoint
    }

    private static func makeRecoveredWalk(from checkpoint: WalkCheckpoint) -> NewWalk {
        let walk = checkpoint.walk
        let recovered = NewWalk(
            workoutType: walk.workoutType,
            distance: walk.distance,
            steps: walk.steps,
            startDate: walk.startDate,
            endDate: walk.endDate,
            isRace: walk.isRace,
            comment: walk.comment,
            isUserModified: walk.isUserModified,
            finishedRecording: false,
            heartRates: walk._heartRates,
            routeData: walk._routeData,
            pauses: walk._pauses,
            workoutEvents: walk._workoutEvents,
            voiceRecordings: walk._voiceRecordings,
            activityIntervals: walk._activityIntervals,
            waypoints: walk._waypoints,
            weatherCondition: walk.weatherCondition,
            weatherTemperature: walk.weatherTemperature,
            weatherHumidity: walk.weatherHumidity,
            weatherWindSpeed: walk.weatherWindSpeed
        )
        recovered.uuid = checkpoint.walkUUID
        return recovered
    }

    static func extractRecordingDirectoryUUID(from walk: TempWalk) -> UUID? {
        for recording in walk._voiceRecordings {
            let components = recording.fileRelativePath.split(separator: "/")
            if components.count >= 2, let dirUUID = UUID(uuidString: String(components[1])) {
                return dirUUID
            }
        }
        return nil
    }

    private static func reconnectOrphanedRecordings(walk: TempWalk, walkUUID: UUID) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings/\(walkUUID.uuidString)")

        guard FileManager.default.fileExists(atPath: recordingsDir.path) else {
            print("\(tag) ORPHAN SCAN — no recordings directory for \(walkUUID.uuidString.prefix(8))...")
            return
        }

        let existingPaths = Set(walk.voiceRecordings.map { $0.fileRelativePath })

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        var orphans: [TempVoiceRecording] = []

        for file in files where file.pathExtension == "m4a" {
            let relativePath = "Recordings/\(walkUUID.uuidString)/\(file.lastPathComponent)"
            guard !existingPaths.contains(relativePath) else { continue }

            let asset = AVURLAsset(url: file)
            let duration = CMTimeGetSeconds(asset.duration)
            guard duration > 0 else { continue }

            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let startDate = modDate.addingTimeInterval(-duration)

            let recording = TempVoiceRecording(
                uuid: UUID(),
                startDate: startDate,
                endDate: modDate,
                duration: duration,
                fileRelativePath: relativePath
            )
            orphans.append(recording)
            print("\(tag) ORPHAN FOUND — \(file.lastPathComponent), duration: \(String(format: "%.1f", duration))s")
        }

        if !orphans.isEmpty {
            walk.appendVoiceRecordings(orphans)
            print("\(tag) ORPHAN SCAN — reconnected \(orphans.count) recording(s)")
        }
    }
}
