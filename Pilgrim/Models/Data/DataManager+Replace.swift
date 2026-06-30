//
//  DataManager+Replace.swift
//
//  Pilgrim
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
import CoreStore

extension DataManager {

    /**
     This function replaces walks in the database: any existing `Walk` sharing
     a UUID with an incoming object is deleted and the incoming version is
     inserted — both inside ONE transaction. A failure (or crash) mid-write
     can therefore never leave the store between "originals deleted" and
     "replacements inserted": CoreStore rolls the whole batch back and the
     pre-existing walks survive untouched. Used by the tended `.pilgrim`
     import, which must never destroy data it cannot re-create.
     - parameter objects: the data sets to be saved; objects whose UUID matches no existing walk are simply inserted
     - parameter dataStack: the stack to operate on; passed explicitly so tests can supply an in-memory stack
     - parameter completion: executed on the main thread once the transaction commits or fails
     - parameter success: indicates the success of the transaction
     - parameter error: more detailed information if an error occurred
     - parameter walks: the `Walk`s that were inserted
     - parameter replacedCount: how many existing walks were deleted in favor of an incoming version
     - parameter capturedRecordingPaths: per replaced walk UUID, the voice-recording `fileRelativePath`s of the deleted version in `startDate` order — the `.pilgrim` format does not carry paths, so callers restore them onto the re-inserted rows
     - warning: Objects of type `Walk` will be rejected, because all objects of that type must already be in the database.
     */
    public static func replaceWalks(
        objects: [WalkInterface],
        dataStack: DataStack,
        completion: @escaping (_ success: Bool, _ error: DataManager.SaveMultipleError?, _ walks: [Walk], _ replacedCount: Int, _ capturedRecordingPaths: [UUID: [String]]) -> Void) {

        let completion = safeClosure(from: completion)

        let validatedObjects = objects.filter { !($0 is Walk) }

        dataStack.perform(asynchronous: { (transaction) -> ([Walk], Int, [UUID: [String]]) in
            try replaceWalksInTransaction(validatedObjects, transaction: transaction)
        }) { (result) in
            switch result {
            case .success(let (createdWalks, replacedCount, capturedPaths)):
                let walks = dataStack.fetchExisting(createdWalks)
                let error: SaveMultipleError? = validatedObjects.count == objects.count ? nil : .notAllSaved
                completion(true, error, walks, replacedCount, capturedPaths)
            case .failure(let error):
                completion(false, .databaseError(error: error), [], 0, [:])
            }
        }
    }

    /// Transaction body for `replaceWalks`. Internal (not private) so tests
    /// can compose it inside a deliberately failing transaction and assert
    /// that CoreStore's rollback leaves the pre-existing walks intact.
    static func replaceWalksInTransaction(
        _ objects: [WalkInterface],
        transaction: AsynchronousDataTransaction
    ) throws -> ([Walk], Int, [UUID: [String]]) {

        var replacedCount = 0
        var capturedPaths: [UUID: [String]] = [:]
        let incomingUUIDs = Set(objects.compactMap { $0.uuid })

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
                replacedCount += 1
            }
        }

        var createdWalks = [Walk]()
        for object in objects {
            createdWalks.append(createWalk(from: object, in: transaction))
        }

        return (createdWalks, replacedCount, capturedPaths)
    }
}
