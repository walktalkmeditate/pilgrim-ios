//
//  DataManager+VoiceRecording.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import CoreData
import CoreStore

extension DataManager {

    // MARK: - Voice Recording

    static func cleanupRecordingFiles(relativePaths: [String]) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for path in relativePaths {
            let url = docs.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: url)
            let parent = url.deletingLastPathComponent()
            let remaining = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            if remaining.isEmpty {
                try? FileManager.default.removeItem(at: parent)
            }
        }
    }

    static func cleanupEmptyRecordingsDirectory() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        let contents = (try? FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: nil)) ?? []
        if contents.isEmpty {
            try? FileManager.default.removeItem(at: recordingsDir)
        }
    }

    public static func deleteRecordingFile(relativePath: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
        let parent = fileURL.deletingLastPathComponent()
        let remaining = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: parent)
        }
        cleanupEmptyRecordingsDirectory()
    }

    public static func recordingFileCount() -> Int {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        guard let enumerator = FileManager.default.enumerator(at: recordingsDir, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "m4a" {
            count += 1
        }
        return count
    }

    public static func deleteAllRecordingFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")
        try? FileManager.default.removeItem(at: recordingsDir)
    }

    /// Completion reports `false` both when the transaction fails AND when
    /// the recording row no longer exists (e.g. replaced by a concurrent
    /// tended import) — callers must not treat either case as "saved".
    /// The `dataStack` parameter exists so tests can supply an in-memory
    /// stack; production call sites use the default.
    /// Analysis fires only when the underlying transaction both succeeded
    /// AND found the row — `updateVoiceRecording`'s completion already
    /// collapses those two conditions into the single `Bool` handed back
    /// here, so there is no third "found" flag to unpack. The trigger stays
    /// local to this function — the shared helper below also serves
    /// WPM/isEnhanced updates, which must never analyze. This is the one
    /// write path shared by batch transcription, single retranscribe, AND
    /// the manual transcript-edit UIs, so an in-place edit recomputes the
    /// context and replaces the stale file when it saves. The detached
    /// utility task keeps analysis off the transcription loop so
    /// `unloadModel()` is never delayed by it.
    public static func updateVoiceRecordingTranscription(
        uuid: UUID,
        transcription: String,
        flaggedFragments: [String] = [],
        transcriptContextStore: TranscriptContextStore = .shared,
        dataStack: DataStack = DataManager.dataStack,
        completion: ((Bool) -> Void)? = nil
    ) {
        updateVoiceRecording(uuid: uuid, dataStack: dataStack, completion: { success in
            if success {
                Task.detached(priority: .utility) {
                    TranscriptContextAnalyzer.analyzeAndStore(
                        recordingUUID: uuid,
                        transcript: transcription,
                        flaggedFragments: flaggedFragments,
                        store: transcriptContextStore
                    )
                }
            }
            completion?(success)
        }, failureLabel: "transcription") {
            $0._transcription .= transcription
        }
    }

    /// Snapshot of every transcribed recording for the Threads backfill —
    /// UUIDs and text only, fetched once, no live objects escape the stack.
    /// Main-actor only: `dataStack.fetchAll` asserts Thread.isMainThread.
    @MainActor
    public static func transcribedRecordingsSnapshot() -> [(uuid: UUID, transcript: String)] {
        let recordings = (try? dataStack.fetchAll(From<VoiceRecording>())) ?? []
        return recordings.compactMap { recording in
            guard let uuid = recording._uuid.value,
                  let transcript = recording._transcription.value,
                  !transcript.isEmpty else { return nil }
            return (uuid, transcript)
        }
    }

    /// Recording UUID → owning walk, for thread aggregation. The walk
    /// relationship on PilgrimV7.VoiceRecording is `_workout` — a frozen
    /// SQL identifier ("workout", PilgrimV7.swift:244) from the OutRun era;
    /// never rename the entity property to "fix" the name. Two dictionary
    /// queries joined by object ID instead of `fetchAll` — the old path
    /// faulted in every recording row plus its walk, one SQL round-trip
    /// each. Main-actor only, matching the other snapshot queries here.
    @MainActor
    public static func voiceRecordingWalkIndex() -> [UUID: (walkUUID: UUID, date: Date)] {
        guard
            let walkRows = try? dataStack.queryAttributes(
                From<Walk>().select(
                    NSDictionary.self,
                    .objectID(),
                    .attribute(\._uuid),
                    .attribute(\._startDate)
                )
            ),
            let recordingRows = try? dataStack.queryAttributes(
                From<VoiceRecording>().select(
                    NSDictionary.self,
                    .attribute(\._uuid),
                    .attribute("workout")
                )
            )
        else { return [:] }

        var walksByObjectID: [NSManagedObjectID: (walkUUID: UUID, date: Date)] = [:]
        for row in walkRows {
            guard let objectID = row["objectID"] as? NSManagedObjectID,
                  let walkUUID = row["id"] as? UUID,
                  let startDate = row["startDate"] as? Date else { continue }
            walksByObjectID[objectID] = (walkUUID, startDate)
        }

        var index: [UUID: (walkUUID: UUID, date: Date)] = [:]
        for row in recordingRows {
            guard let uuid = row["id"] as? UUID,
                  let walkObjectID = row["workout"] as? NSManagedObjectID,
                  let walk = walksByObjectID[walkObjectID] else { continue }
            index[uuid] = walk
        }
        return index
    }

    public static func updateVoiceRecordingWordsPerMinute(
        uuid: UUID,
        wordsPerMinute: Double,
        dataStack: DataStack = DataManager.dataStack,
        completion: ((Bool) -> Void)? = nil
    ) {
        updateVoiceRecording(uuid: uuid, dataStack: dataStack, completion: completion, failureLabel: "WPM") {
            $0._wordsPerMinute .= wordsPerMinute
        }
    }

    public static func updateVoiceRecordingIsEnhanced(
        uuid: UUID,
        isEnhanced: Bool,
        dataStack: DataStack = DataManager.dataStack,
        completion: ((Bool) -> Void)? = nil
    ) {
        updateVoiceRecording(uuid: uuid, dataStack: dataStack, completion: completion, failureLabel: "isEnhanced") {
            $0._isEnhanced .= isEnhanced
        }
    }

    private static func updateVoiceRecording(
        uuid: UUID,
        dataStack: DataStack,
        completion: ((Bool) -> Void)?,
        failureLabel: String,
        applyEdit: @escaping (VoiceRecording) -> Void
    ) {
        dataStack.perform(asynchronous: { transaction -> Bool in
            guard let recording = transaction.edit(
                queryObject(from: uuid, transaction: transaction) as VoiceRecording?
            ) else {
                return false
            }
            applyEdit(recording)
            return true
        }) { result in
            switch result {
            case .success(let found):
                if !found {
                    print("[DataManager] \(failureLabel) update skipped — recording \(uuid) no longer exists")
                }
                completion?(found)
            case .failure(let error):
                print("[DataManager] Failed to update \(failureLabel) for \(uuid): \(error)")
                completion?(false)
            }
        }
    }
}
