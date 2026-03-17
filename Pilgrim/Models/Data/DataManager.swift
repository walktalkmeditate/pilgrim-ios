//
//  DataManager.swift
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
import CoreStore
import CoreLocation

/// A structure holding static instances and methods for database management and manipulation
struct DataManager {
    
    // MARK: - Database setup
    
    /// static optional instance of the local storage holding the walk data
    private static var storage: SQLiteStore?
    
    /// The size of the local storage in bytes; if `nil` it could not be calculated.
    public static var diskSize: Int? {
        if let size = storage?.fileSize() {
            return Int(size)
        }
        return nil
    }
    
    /**
     The primary `DataStack` used by the `DataManager`.
     - warning: make sure `dataStack` is initialised by calling `DataManager.setup(dataModel:completion:migration:)` accessing the property will lead to a fatal error otherwise
     */
    public static var dataStack: DataStack!
    
    /**
     This function sets up the data management by initialising the `dataStack` and loading the underlying sqlite storage of the database
     - parameter dataModel: an `DataModelProtocol` conforming `Type` being used to setup the data management
     - parameter completion: the closure being called on a successful completion of setting up data management
     - parameter migration: the closure being called on the event of a migration happening, including a `Progress` object indicating the progress of the migration
     - warning: If this method fails it does so in a fatal error, the app will crash as a result.
     */
    public static func setup(dataModel: DataModelProtocol.Type = PilgrimV6.self, completion: @escaping (DataManager.SetupError?) -> Void, migration: @escaping (Progress) -> Void) {
        
        let completion = safeClosure(from: completion)
        
        // setup storage
        let storage = SQLiteStore(
            fileName: "Pilgrim.sqlite",
            migrationMappingProviders: dataModel.migrationChain.compactMap(
                { (type) -> CustomSchemaMappingProvider? in
                    return type.mappingProvider
                }
            ),
            localStorageOptions: .none
        )
        self.storage = storage
        
        // select relevant versions
        let currentVersion = storage.currentORModel(from: dataModel.migrationChain)
        var relevants = dataModel.migrationChain.filter { (type) -> Bool in
            // relevent version should include the final type (dataModel) and all intermediate models, but it is important that they are successors of current version of the storage otherwise the models might be incompatible
            type == dataModel || (currentVersion != nil ? type is IntermediateDataModelProtocol && (type.isSuccessor(to: currentVersion!) || type == currentVersion) : false)
        }
            
        let destinationModel = relevants.removeFirst()
        dataStack = DataStack(oRMigrationChain: dataModel.migrationChain, oRDataModel: destinationModel)
        
        // adding storage
        if let progress = dataStack.addStorage(
            storage,
            completion: { result in
                switch result {
                case .success(_):
                    
                    if let intermediate = destinationModel as? IntermediateDataModelProtocol.Type {
                        if !intermediate.intermediateMappingActions(dataStack) {
                            print("[DataManager] Intermediate mapping actions of \(destinationModel) were unsuccessful")
                            completion(.intermediateMappingActionsFailed(version: intermediate))
                            return
                        }
                    }
                    
                    if relevants.first != nil {
                        setup(dataModel: dataModel, completion: completion, migration: migration)
                    } else {
                        completion(nil)
                    }
                    
                case .failure(let error):
                    print("[DataManager] Failed to add storage for \(dataModel)\nError: \(error)")
                    completion(.failedToAddStorage(error: error))
                }
            }
        ) {
            // handling migration
            DispatchQueue.main.async {
                migration(progress)
            }
        }
    }
    
    // MARK: - Walk
    
    /**
     This function saves a walk to the database.
     - parameter object: the data set to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving the walk
     - parameter error: gives more detailed information on an error if one occured
     - parameter walk: holds the `Walk` if saving it succeeded
     - note: Objects conforming to `EventInterface` and associated with the provided object will not be added to the database
     - warning: An `object` of Type `Walk` will be rejected with an `.alreadySaved` error, because all objects of that type must already be in the database.
     */
    public static func saveWalk(
        object: WalkInterface,
        completion: @escaping (_ success: Bool, _ error: DataManager.SaveError?, _ walk: Walk?) -> Void) {

        let completion = safeClosure(from: completion)

        saveWalks(
            objects: [object],
            completion: { success, error, walks in
                if let walk = walks.first {
                    completion(true, nil, walk)
                } else {
                    
                    switch error {
                    case .notAllSaved:
                        completion(false, .alreadySaved, nil)
                    case .notAllValid:
                        completion(false, .notValid, nil)
                    case .databaseError(let error):
                        completion(false, .databaseError(error: error), nil)
                    default:
                        // this case should never occur
                        completion(false, nil, nil)
                    }
                }
            }
        )
    }
    
    /**
     This function saves multiple walks to the database.
     - parameter objects: the data sets to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving walks; this will also be `true` if not all walks were valid and some have been excluded
     - parameter error: gives more detailed information on an error if one occured
     - parameter walks: holds the `Walk`s that were successfully saved
     - note: Objects conforming to `EventInterface` and associated with the provided objects will not be added to the database
     - warning: Objects of type `Walk` will be rejected, because all objects of that type must already be in the database.
     */
    public static func saveWalks(
        objects: [WalkInterface],
        completion: @escaping (_ success: Bool, _ error: DataManager.SaveMultipleError?, _ walks: [Walk]) -> Void) {
        
        let completion = safeClosure(from: completion)
        
        // filtering for Walk class and already saved
        let filteredObjects = objects.filter { (object) -> Bool in
            if object is Walk {
                return false
            } else if let uuid = object.uuid, objectHasDuplicate(uuid: uuid, objectType: Walk.self) {
                return false
            }
            return true
        }
        
        // Todo: Validation
        let validatedObjects = filteredObjects
        
        dataStack.perform(asynchronous: { (transaction) -> [Walk] in
            
            var walks = [Walk]()

            for object in validatedObjects {

                let walk = transaction.create(Into<Walk>())
                walk._uuid .= object.uuid ?? UUID()
                walk._workoutType .= object.workoutType
                walk._distance .= object.distance
                walk._steps .= object.steps
                walk._startDate .= object.startDate
                walk._endDate .= object.endDate
                walk._burnedEnergy .= object.burnedEnergy
                walk._isRace .= object.isRace
                walk._comment .= object.comment
                walk._isUserModified .= object.isUserModified
                walk._healthKitUUID .= object.healthKitUUID

                walk._ascend .= object.ascend
                walk._descend .= object.descend
                walk._activeDuration .= object.activeDuration
                walk._pauseDuration .= object.pauseDuration
                walk._dayIdentifier .= object.dayIdentifier
                walk._talkDuration .= object.talkDuration
                walk._meditateDuration .= object.meditateDuration

                walk._favicon .= object.favicon

                persistRelatedEntities(from: object, to: walk, in: transaction)
                walks.append(walk)

            }

            return walks

        }) { (result) in
            switch result {
            case .success(let savedWalks):
                let walks = dataStack.fetchExisting(savedWalks)

                if walks.count == objects.count {
                    completion(true, nil, walks)
                } else if walks.count == filteredObjects.count {
                    completion(true, .notAllSaved, walks)
                } else {
                    // last case: walks.count must be equal to validatedObjects.count
                    completion(true, .notAllValid, walks)
                }
                
            case .failure(let error):
                completion(false, .databaseError(error: error), [])
            }
        }
        
    }

    private static func persistRelatedEntities(
        from source: WalkInterface,
        to walk: Walk,
        in transaction: BaseDataTransaction
    ) {
        for tempPause in source.pauses {
            let pause = transaction.create(Into<WalkPause>())
            pause._uuid .= tempPause.uuid ?? UUID()
            pause._startDate .= tempPause.startDate
            pause._endDate .= tempPause.endDate
            pause._pauseType .= tempPause.pauseType
            pause._workout .= walk
        }

        for tempWalkEvent in source.workoutEvents {
            let walkEvent = transaction.create(Into<WalkEvent>())
            walkEvent._uuid .= tempWalkEvent.uuid ?? UUID()
            walkEvent._eventType .= tempWalkEvent.eventType
            walkEvent._timestamp .= tempWalkEvent.timestamp
            walkEvent._workout .= walk
        }

        for tempSample in source.routeData {
            let routeSample = transaction.create(Into<RouteDataSample>())
            routeSample._uuid .= tempSample.uuid ?? UUID()
            routeSample._latitude .= tempSample.latitude
            routeSample._longitude .= tempSample.longitude
            routeSample._altitude .= tempSample.altitude
            routeSample._timestamp .= tempSample.timestamp
            routeSample._horizontalAccuracy .= tempSample.horizontalAccuracy
            routeSample._verticalAccuracy .= tempSample.verticalAccuracy
            routeSample._speed .= tempSample.speed
            routeSample._direction .= tempSample.direction
            routeSample._workout .= walk
        }

        for tempSample in source.heartRates {
            let heartRateSample = transaction.create(Into<HeartRateDataSample>())
            heartRateSample._uuid .= tempSample.uuid ?? UUID()
            heartRateSample._heartRate .= tempSample.heartRate
            heartRateSample._timestamp .= tempSample.timestamp
            heartRateSample._workout .= walk
        }

        for tempRecording in source.voiceRecordings {
            let recording = transaction.create(Into<VoiceRecording>())
            recording._uuid .= tempRecording.uuid ?? UUID()
            recording._startDate .= tempRecording.startDate
            recording._endDate .= tempRecording.endDate
            recording._duration .= tempRecording.duration
            recording._fileRelativePath .= tempRecording.fileRelativePath
            recording._transcription .= tempRecording.transcription
            recording._wordsPerMinute .= tempRecording.wordsPerMinute
            recording._isEnhanced .= tempRecording.isEnhanced
            recording._workout .= walk
        }

        for tempInterval in source.activityIntervals {
            let interval = transaction.create(Into<ActivityInterval>())
            interval._uuid .= tempInterval.uuid ?? UUID()
            interval._activityType .= tempInterval.activityType
            interval._startDate .= tempInterval.startDate
            interval._endDate .= tempInterval.endDate
            interval._workout .= walk
        }

        for tempWaypoint in source.waypoints {
            let waypoint = transaction.create(Into<Waypoint>())
            waypoint._uuid .= tempWaypoint.uuid ?? UUID()
            waypoint._latitude .= tempWaypoint.latitude
            waypoint._longitude .= tempWaypoint.longitude
            waypoint._label .= tempWaypoint.label
            waypoint._icon .= tempWaypoint.icon
            waypoint._timestamp .= tempWaypoint.timestamp
            waypoint._workout .= walk
        }
    }

    private static func persistNewRelatedEntities(
        from source: WalkInterface,
        to walk: Walk,
        in transaction: BaseDataTransaction
    ) {
        for tempPause in source.pauses where tempPause.uuid == nil {
            let pause = transaction.create(Into<WalkPause>())
            pause._uuid .= tempPause.uuid ?? UUID()
            pause._startDate .= tempPause.startDate
            pause._endDate .= tempPause.endDate
            pause._pauseType .= tempPause.pauseType
            pause._workout .= walk
        }

        for tempWalkEvent in source.workoutEvents where tempWalkEvent.uuid == nil {
            let walkEvent = transaction.create(Into<WalkEvent>())
            walkEvent._uuid .= tempWalkEvent.uuid ?? UUID()
            walkEvent._eventType .= tempWalkEvent.eventType
            walkEvent._timestamp .= tempWalkEvent.timestamp
            walkEvent._workout .= walk
        }

        for tempSample in source.routeData where tempSample.uuid == nil {
            let routeSample = transaction.create(Into<RouteDataSample>())
            routeSample._uuid .= tempSample.uuid ?? UUID()
            routeSample._latitude .= tempSample.latitude
            routeSample._longitude .= tempSample.longitude
            routeSample._altitude .= tempSample.altitude
            routeSample._timestamp .= tempSample.timestamp
            routeSample._horizontalAccuracy .= tempSample.horizontalAccuracy
            routeSample._verticalAccuracy .= tempSample.verticalAccuracy
            routeSample._speed .= tempSample.speed
            routeSample._direction .= tempSample.direction
            routeSample._workout .= walk
        }

        for tempSample in source.heartRates where tempSample.uuid == nil {
            let heartRateSample = transaction.create(Into<HeartRateDataSample>())
            heartRateSample._uuid .= tempSample.uuid ?? UUID()
            heartRateSample._heartRate .= tempSample.heartRate
            heartRateSample._timestamp .= tempSample.timestamp
            heartRateSample._workout .= walk
        }

        for tempRecording in source.voiceRecordings where tempRecording.uuid == nil {
            let recording = transaction.create(Into<VoiceRecording>())
            recording._uuid .= tempRecording.uuid ?? UUID()
            recording._startDate .= tempRecording.startDate
            recording._endDate .= tempRecording.endDate
            recording._duration .= tempRecording.duration
            recording._fileRelativePath .= tempRecording.fileRelativePath
            recording._transcription .= tempRecording.transcription
            recording._wordsPerMinute .= tempRecording.wordsPerMinute
            recording._isEnhanced .= tempRecording.isEnhanced
            recording._workout .= walk
        }

        for tempInterval in source.activityIntervals where tempInterval.uuid == nil {
            let interval = transaction.create(Into<ActivityInterval>())
            interval._uuid .= tempInterval.uuid ?? UUID()
            interval._activityType .= tempInterval.activityType
            interval._startDate .= tempInterval.startDate
            interval._endDate .= tempInterval.endDate
            interval._workout .= walk
        }

        for tempWaypoint in source.waypoints where tempWaypoint.uuid == nil {
            let waypoint = transaction.create(Into<Waypoint>())
            waypoint._uuid .= tempWaypoint.uuid ?? UUID()
            waypoint._latitude .= tempWaypoint.latitude
            waypoint._longitude .= tempWaypoint.longitude
            waypoint._label .= tempWaypoint.label
            waypoint._icon .= tempWaypoint.icon
            waypoint._timestamp .= tempWaypoint.timestamp
            waypoint._workout .= walk
        }
    }

    /**
     This function updates a walk from a data set referencing the walk with its universally unique identifier.
     - parameter object: the data set containing all updates
     - parameter completion: the closure being perfomed upon finishing the updating process
     - parameter success: indicates the success of the operation
     - parameter error: gives more detailed information on an error if one occured
     - parameter walk: holds the `Walk` if updating it succeeded
     - warning: Objects of type `Walk` will be rejected, because all objects of that type must already hold the provided data.
     */
    public static func updateWalk(object: WalkInterface, completion: @escaping (_ success: Bool, _ error: DataManager.UpdateError?, _ walk: Walk?) -> Void) {
        
        let completion = safeClosure(from: completion)
        
        // check for Walk class
        if object is Walk {
            completion(false, .notAltered, nil)
            return
        }
        
        // check for uuid {
        guard let uuid = object.uuid else {
            completion(false, .notSaved, nil)
            return
        }
        
        // Todo: Validation
        
        dataStack.perform(asynchronous: { (transaction) -> Walk? in
            
            if let walk = transaction.edit(queryObject(from: uuid, transaction: transaction) as Walk?) {

                walk._uuid .= object.uuid ?? UUID()
                walk._workoutType .= object.workoutType
                walk._distance .= object.distance
                walk._steps .= object.steps
                walk._startDate .= object.startDate
                walk._endDate .= object.endDate
                walk._burnedEnergy .= object.burnedEnergy
                walk._isRace .= object.isRace
                walk._comment .= object.comment
                walk._isUserModified .= object.isUserModified
                walk._healthKitUUID .= object.healthKitUUID

                walk._ascend .= object.ascend
                walk._descend .= object.descend
                walk._activeDuration .= object.activeDuration
                walk._pauseDuration .= object.pauseDuration
                walk._dayIdentifier .= object.dayIdentifier
                walk._talkDuration .= object.talkDuration
                walk._meditateDuration .= object.meditateDuration
                walk._favicon .= object.favicon

                persistNewRelatedEntities(from: object, to: walk, in: transaction)
                return walk
                
            } else {
                return nil
            }
            
        }) { (result) in
            switch result {
            case .success(let savedWalk):
                if let savedWalk = savedWalk, let walk = dataStack.fetchExisting(savedWalk) {
                    completion(true, nil, walk)
                } else {
                    completion(false, .databaseError(error: CoreStoreError.persistentStoreNotFound(entity: Walk.self)), nil)
                }
            case .failure(let error):
                completion(false, .databaseError(error: error), nil)
            }
        }
    }
    
    // MARK: - Voice Recording

    private static func cleanupRecordingFiles(relativePaths: [String]) {
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

    private static func cleanupEmptyRecordingsDirectory() {
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

    public static func updateVoiceRecordingTranscription(uuid: UUID, transcription: String) {
        dataStack.perform(asynchronous: { transaction -> Void in
            if let recording = transaction.edit(
                queryObject(from: uuid, transaction: transaction) as VoiceRecording?
            ) {
                recording._transcription .= transcription
            }
        }) { result in
            if case .failure(let error) = result {
                print("[DataManager] Failed to update transcription: \(error)")
            }
        }
    }

    public static func updateVoiceRecordingWordsPerMinute(uuid: UUID, wordsPerMinute: Double) {
        dataStack.perform(asynchronous: { transaction -> Void in
            if let recording = transaction.edit(
                queryObject(from: uuid, transaction: transaction) as VoiceRecording?
            ) {
                recording._wordsPerMinute .= wordsPerMinute
            }
        }) { result in
            if case .failure(let error) = result {
                print("[DataManager] Failed to update WPM for \(uuid): \(error)")
            }
        }
    }

    // MARK: - Favicon

    public static func setFavicon(walkID: UUID, favicon: WalkFavicon?) {
        dataStack.perform(asynchronous: { transaction -> Void in
            if let walk = transaction.edit(
                queryObject(from: walkID, transaction: transaction) as Walk?
            ) {
                walk._favicon .= favicon?.rawValue
            }
        }) { result in
            if case .failure(let error) = result {
                print("[DataManager] Failed to set favicon: \(error)")
            }
        }
    }

    // MARK: - Event
    
    /**
     Saves an event to the database.
     - parameter object: the data set to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving the event
     - parameter error: gives more detailed information on an error if one occured
     - parameter event: holds the `Event` if saving it succeeded
     - note: Objects conforming to `WalkInterface` and associated with the provided data sets will not be added to the database, rather the data manager will try to query walk objects from only the provided `UUID`s in the `WalkInterface` objects and attach them to the `Event`. For that it is important that these walk objects are already saved to the database, otherwise a reference cannot be established.
     - warning: An `object` of Type `Event` will be rejected with an `.alreadySaved` error, because all objects of that type must already be in the database.
     */
    public static func saveEvent(object: EventInterface, completion: @escaping (_ success: Bool, _ error: DataManager.SaveError?, _ event: Event?) -> Void) {
        
        let completion = safeClosure(from: completion)
        
        saveEvents(
            objects: [object],
            completion: { success, error, events in
                if let event = events.first {
                    completion(true, nil, event)
                } else {
                    
                    switch error {
                    case .notAllSaved:
                        completion(false, .alreadySaved, nil)
                    case .notAllValid:
                        completion(false, .notValid, nil)
                    case .databaseError(let error):
                        completion(false, .databaseError(error: error), nil)
                    default:
                        // this case should never occur
                        completion(false, nil, nil)
                    }
                }
            }
        )
        
    }
    
    /**
     Saves multiple events to the database.
     - parameter objects: the data sets to be saved to the database
     - parameter completion: the closure being executed on the main thread as soon as the saving either succeeds or fails
     - parameter success: indicates the success of saving the events
     - parameter error: gives more detailed information on an error if one occured
     - parameter events: holds the `Event`s if saving them succeeded
     - note: Objects conforming to `WalkInterface` and associated with the provided data sets will not be added to the database, rather the data manager will try to query walk objects from only the provided `UUID`s in the `WalkInterface` objects and attach them to the `Event`s. For that it is important that these walk objects are already saved to the database, otherwise a reference cannot be established.
     - warning: `objects` of Type `Event` will be rejected with an `.alreadySaved` error, because all objects of that type must already be in the database.
     */
    public static func saveEvents(objects: [EventInterface], completion: @escaping (_ success: Bool, _ error: DataManager.SaveMultipleError?, _ events: [Event]) -> Void) {
        
        let completion = safeClosure(from: completion)
        
        let filteredObjects = objects.filter { (object) -> Bool in
            if object is Event {
                return false
            } else if let uuid = object.uuid, objectHasDuplicate(uuid: uuid, objectType: Event.self) {
                return false
            }
            return true
        }
        
        // Todo: Validation
        let validatedObjects = filteredObjects
        
        dataStack.perform(asynchronous: { (transaction) -> [Event] in
            
            var events = [Event]()
            
            for object in validatedObjects {
                
                let event = transaction.create(Into<Event>())
                
                event._uuid .= object.uuid ?? UUID()
                event._title .= object.title
                event._comment .= object.comment
                event._startDate .= object.startDate
                event._endDate .= object.endDate
                
                let walkUUIDs = object.workouts.compactMap { $0.uuid }

                if let walks = try? transaction.fetchAll(
                    From<Walk>()
                        .where({
                            Where<Walk>(walkUUIDs.containsOptional($0.uuid))
                        })
                        .orderBy(.ascending(\._startDate))
                ) {
                    event._workouts .= walks
                }
                
                events.append(event)
                
            }
            
            return events
        
        }) { (result) in
            switch result {
            case .success(let tempEvents):
                let events = dataStack.fetchExisting(tempEvents)
                
                if events.count == objects.count {
                    completion(true, nil, events)
                } else if events.count == filteredObjects.count {
                    completion(true, .notAllSaved, events)
                } else {
                    // last case: events.count must be equal to validatedObjects.count
                    completion(true, .notAllValid, events)
                }
            case .failure(let error):
                completion(false, .databaseError(error: error), [])
            }
        }
    }
    
    /**
     This function updates an event from a data set referencing the event with its universally unique identifier.
     - parameter object: the data set containing all updates
     - parameter completion: the closure being perfomed upon finishing the updating process
     - parameter success: indicates the success of the operation
     - parameter error: gives more detailed information on an error if one occured
     - parameter event: holds the `Event` if updating it succeeded
     - warning: Objects of type `Event` will be rejected, because all objects of that type must already hold the provided data.
     */
    public static func updateEvent(object: EventInterface, completion: @escaping (_ success: Bool, _ error: DataManager.UpdateError?, _ event: Event?) -> Void) {
        
        let completion = safeClosure(from: completion)
        
        // check for Walk class
        if object is Event {
            completion(false, .notAltered, nil)
            return
        }
        
        // check for uuid {
        guard let uuid = object.uuid else {
            completion(false, .notSaved, nil)
            return
        }
        
        // Todo: Validation
        
        dataStack.perform(asynchronous: { (transaction) -> Event? in
            
            if let event = transaction.edit(queryObject(from: uuid, transaction: transaction) as Event?) {
                
                event._uuid .= object.uuid ?? UUID()
                event._title .= object.title
                event._comment .= object.comment
                event._startDate .= object.startDate
                event._endDate .= object.endDate
                
                for walkObject in object.workouts {

                    guard !(walkObject is Walk), let uuid = walkObject.uuid, let walk = transaction.edit(queryObject(from: uuid) as Walk?), !walk._events.contains(event) else {
                        continue
                    }

                    var set = walk._events.value
                    set.insert(event)
                    walk._events .= set

                }
                
                return event
                
            } else {
                return nil
            }
            
        }) { (result) in
            switch result {
            case .success(let tempEvent):
                if let tempEvent = tempEvent, let event = dataStack.fetchExisting(tempEvent) {
                    completion(true, nil, event)
                } else {
                    completion(false, .databaseError(error: CoreStoreError.persistentStoreNotFound(entity: Event.self)), nil)
                }
            case .failure(let error):
                completion(false, .databaseError(error: error), nil)
            }
        }
        
    }
    
    // MARK: - Delete
    
    /**
     This function deletes an `DataTypeProtocol` object from the database.
     - parameter object: the object being deleted
     - parameter completion: the closure being perfomed upon finishing the deletion process
     - parameter success: indicates the success of the operation
     - parameter error: gives more detailed information on an error if one occured
     */
    public static func deleteObject<ObjectType: DataTypeProtocol>(object: ObjectType, completion: @escaping (_ success: Bool, _ error: DataManager.DeleteError?) -> Void) {

        dataStack.perform(asynchronous: { (transaction) -> [String] in

            var filePaths: [String] = []
            if let walk = object as? Walk,
               let editable = transaction.edit(walk) {
                filePaths = editable._voiceRecordings.value.compactMap { $0._fileRelativePath.value }
            }
            transaction.delete(object)
            return filePaths

        }) { (result) in
            switch result {
            case .success(let filePaths):
                cleanupRecordingFiles(relativePaths: filePaths)
                completion(true, nil)
            case .failure(let error):
                completion(false, .databaseError(error: error))
            }
        }

    }
    
    /**
     This function deletes all data objects in the database.
     - parameter completion: the closure being perfomed upon finishing the deletion process
     - parameter success: indicates the success of the operation
     - parameter error: gives more detailed information on an error if one occured
     */
    public static func deleteAll(completion: @escaping (_ success: Bool, _ error: DataManager.DeleteError?) -> Void) {

        var deletionError: CoreStoreError?

        let allRecordingPaths: [String] = (try? dataStack.fetchAll(From<VoiceRecording>()))?.compactMap { $0._fileRelativePath.value } ?? []

        dataStack.perform(asynchronous: { (transaction) -> Void in

            do {
                try transaction.deleteAll(From<Walk>())
                try transaction.deleteAll(From<WalkPause>())
                try transaction.deleteAll(From<WalkEvent>())
                try transaction.deleteAll(From<RouteDataSample>())
                try transaction.deleteAll(From<HeartRateDataSample>())
                try transaction.deleteAll(From<VoiceRecording>())
                try transaction.deleteAll(From<ActivityInterval>())
                try transaction.deleteAll(From<Waypoint>())
                try transaction.deleteAll(From<Event>())
            } catch {
                deletionError = error as? CoreStoreError
            }

        }) { (result) in
            switch result {
            case .success(_):
                cleanupRecordingFiles(relativePaths: allRecordingPaths)
                cleanupEmptyRecordingsDirectory()
                if let error = deletionError {
                    completion(true, .databaseError(error: error))
                } else {
                    completion(true, nil)
                }
            case .failure(let error):
                completion(false, .databaseError(error: error))
            }
        }

    }
    
    // MARK: - Monitoring
    
    /// A `CoreStore.ListMonitor` to observe changes in the database and refresh the home view.
    public static let walkMonitor = dataStack.monitorList(
        From<Walk>()
            .orderBy(.descending(\._startDate))
            .where(Where<Walk>(true))
    )
    
}
