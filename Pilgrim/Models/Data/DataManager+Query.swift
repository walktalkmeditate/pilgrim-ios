//
//  DataManager+Query.swift
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

extension DataManager {
    
    // MARK: - General
    
    /**
     Queries an object comforming to `DataTypeProtocol` with the provided `UUID` from the database.
     - parameter whereClause: the `CoreStore.Where` clause used for selection of the object
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the object needs to be queried during a transaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `DataTypeProtocol` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObject<ObjectType: DataTypeProtocol>(from whereClause: Where<ObjectType>, transaction: AsynchronousDataTransaction? = nil) -> ObjectType? {
        
        let object = try? (transaction as FetchableSource? ?? dataStack).fetchOne(From<ObjectType>().where(whereClause))
        return object
    }
    
    /**
     Queries an object comforming to `DataTypeProtocol` with the provided `UUID` from the database.
     - parameter whereClause: the `CoreStore.Where` clause used for selection of the object
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the object needs to be queried during a transaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `DataTypeProtocol` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObjects<ObjectType: DataTypeProtocol>(from whereClause: Where<ObjectType>, transaction: AsynchronousDataTransaction? = nil) -> [ObjectType] {
        
        let objects = try? (transaction as FetchableSource? ?? dataStack).fetchAll(From<ObjectType>().where(whereClause))
        return objects ?? []
    }
    
    /**
     Queries an object comforming to `DataTypeProtocol` with the provided `UUID` from the database.
     - parameter uuid: the `UUID` of the object that is supposed to be returned; if `nil` this function will return immediately with no value
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the object needs to be queried during a transaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `DataTypeProtocol` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObject<ObjectType: DataTypeProtocol>(from uuid: UUID?, transaction: AsynchronousDataTransaction? = nil) -> ObjectType? {
        
        guard let uuid = uuid else {
            return nil
        }
        
        return queryObject(from: \._uuid == uuid, transaction: transaction)
    }
    
    /**
     Queries an object comforming to `DataTypeProtocol` with the provided object's uuid from the database.
     - parameter anyObject: any object representing the wanted database object to be returned
     - parameter transaction: an optional `AsynchronousDataTransaction` to be provided if the object needs to be queried during a transaction; if `nil` the object will be queried from the `DataManager.dataStack`
     - returns: the wanted `DataTypeProtocol` object if one could be found in the database; if the object could not be found, this function will return `nil`
     */
    public static func queryObject<ObjectType: DataTypeProtocol>(from anyObject: DataInterface, transaction: AsynchronousDataTransaction? = nil) -> ObjectType? {
        
        return queryObject(from: anyObject.uuid, transaction: transaction)
    }
    
    /**
     Queries the count for objects of the given `DataTypeProtocol` and `UUID` returning whether it has duplicates in the database.
     - parameter uuid: the `UUID` of the object being checked for duplicates; if `nil` this function will return immediately with `false`
     - parameter objectType: the type of the object being checked for duplicates
     - returns: `true` if the queried count is anything other than 0 meaning there are objects with the given `UUID` present in the database.
     */
    public static func objectHasDuplicate<ObjectType: DataTypeProtocol>(uuid: UUID?, objectType: ObjectType.Type) -> Bool {
        
        guard let uuid = uuid else {
            return false
        }
        
        if let count = try? dataStack.fetchCount(From<ObjectType>().where(\._uuid == uuid)) {
            return count != 0
        }
        
        return false
        
    }
    
    /**
     Fetches the count of saved objects of a specific `ObjectType` inside the database.
     - parameter of: the kind of `ObjectType` to fetch the count of
     - returns: the number of counted objects as an `Int`
     */
    public static func fetchCount<ObjectType: DataTypeProtocol>(of _: ObjectType.Type) -> Int {
        let count = try? dataStack.fetchCount(From<ObjectType>())
        return count ?? 0
    }
    
    // MARK: - Walk Route
    
    /**
     Queries the route of a walk and converts each route sample into the corresponding `CLLocationDegrees`.
     - parameter walk: the object the route is going to be queried from, any `WalkInterface` will be accepted
     - parameter completion: the closure being called upon completion of the query
     - parameter success: indicates whether or not the query succeeded
     - parameter error: provides more detail on a query failure if one occured
     - parameter coordinates: the queried array of `CLLocationCoordinate2D`
     */
    public static func asyncLocationCoordinatesQuery(for walk: WalkInterface, completion: @escaping (_ error: LocationQueryError?, _ coordinates: [CLLocationCoordinate2D]) -> Void) {

        var error: LocationQueryError?

        dataStack.perform(asynchronous: { (transaction) -> [CLLocationCoordinate2D] in

            guard let walk = (walk as? Walk) ?? queryObject(from: walk.uuid, transaction: transaction) else {
                error = .notSaved
                return []
            }
            
            let samples = walk._routeData.value
            guard !samples.isEmpty else {
                error = .noRouteData
                return []
            }
            
            return samples.map { (sample) -> CLLocationCoordinate2D in
                CLLocationCoordinate2D(
                    latitude: sample._latitude.value,
                    longitude: sample._longitude.value
                )
            }
            
        }) { (result) in
            switch result {
            case .success(let coordinates):
                completion(error, coordinates)
            case .failure(let error):
                completion(.databaseError(error: error), [])
            }
        }
    }
    
    // MARK: - Walk Stats
    
    /**
     Queries the `WalkStats` object of a walk asynchronously.
     - parameter walk: the walk object used to construct the stats object
     - parameter completion: a closure performed on completion of querying the data
     */
    public static func queryWalkStats(
        for walk: WalkInterface,
        completion: @escaping (WalkStats?) -> Void
    ) {
        dataStack.perform(asynchronous: { (transaction) -> WalkStats? in

            guard let walk: Walk = queryObject(from: walk, transaction: transaction) else { return nil }
            return WalkStats(walk: walk)
            
        }) { (result) in
            switch result {
            case .success(let stats):
                completion(stats)
            case .failure:
                completion(nil)
            }
        }
    }
    
    // MARK: - Sectioned Metrics
    
    /**
     Queries a specific metric from specified samples relative to the start date of the walk and grouped by if they are paused or not.
     - parameter walk: the walk object used to query samples from
     - parameter samples: a keypath pointing to the samples of which the matric should be taken
     - parameter metric: a keypath pointing to the metric of the before specified sample
     - parameter includeSamples: a boolean indicating whether the data should include the samples specified
     - parameter completion: a closure performed on completion of querying the data
     */
    public static func querySectionedMetrics <SampleType: Collection, MetricType: Any> (
        from walk: WalkInterface,
        samples samplesPath: KeyPath<Walk, SampleType>,
        metric metricPath: KeyPath<SampleType.Element, MetricType>,
        includeSamples: Bool = false,
        completion: @escaping (WalkStatsSeries<Bool, MetricType, SampleType.Element>) -> Void
    ) where SampleType.Element: SampleInterface {

        dataStack.perform(asynchronous: { (transaction) -> WalkStatsSeries<Bool, MetricType, SampleType.Element> in

            guard let walk: Walk = queryObject(from: walk, transaction: transaction) else {
                return []
            }
            
            var objects: [WalkStatsSeries<Bool, MetricType, SampleType.Element>.RawSection] = []
            var currentlyPaused = false
            var currentData = [(timestamp: TimeInterval, value: MetricType, object: SampleType.Element?)]()
            
            for sample in walk[keyPath: samplesPath] {
                
                if currentlyPaused != walk.pauses.contains(where: { $0.contains(sample.timestamp) }) {
                    if !currentData.isEmpty {
                        objects.append((currentlyPaused, currentData))
                    }
                    currentlyPaused.toggle()
                }
                currentData.append((
                    timestamp: sample.timestamp.distance(to: walk.startDate),
                    value: sample[keyPath: metricPath],
                    object: includeSamples ? sample : nil
                ))
            }
            
            objects.append((currentlyPaused, currentData))
            return WalkStatsSeries(sections: objects)
            
        }) { (result) in
            switch result {
            case .success(let series):
                completion(series)
            case .failure:
                completion([])
            }
        }
    }
    
    // MARK: - Backup
    
    /**
     Queries the data required to create a backup.
     - parameter inclusionType: the type of data that is supposed to be included in the backup
     - parameter completion: a closure providing the queried data and an optional error if something went wrong
     */
    public static func queryBackupData(for inclusionType: ExportManager.DataInclusionType, completion: @escaping (_ error: BackupQueryError?, _ data: Data?) -> Void) {
        
        var fetchSucceeded = false
        
        dataStack.perform(asynchronous: { (transaction) -> Data? in
            
            do {
                
                let tempWalks: [TempWalk]
                let tempEvents: [TempEvent]
                
                switch inclusionType {
                case .all:
                    tempWalks = try transaction.fetchAll(From<Walk>()).map { $0.asTemp }
                    tempEvents = try transaction.fetchAll(From<Event>()).map { $0.asTemp }
                    
                case .someWalks(let includedWalks):
                    tempWalks = includedWalks.compactMap({ walkRep -> Walk? in
                        queryObject(from: walkRep, transaction: transaction)
                    }).map { $0.asTemp }
                    tempEvents = []
                    
                case .someEvents(let includedEvents):
                    var walks = [Walk]()
                    let events = includedEvents.compactMap({ eventRep -> Event? in
                        let event: Event? = queryObject(from: eventRep, transaction: transaction)
                        if let event = event {
                            for walk in event._workouts.value where !walks.contains(walk) {
                                walks.append(walk)
                            }
                        }
                        return event
                    })
                    tempWalks = walks.map { $0.asTemp }
                    tempEvents = events.map { $0.asTemp }
                }
                
                fetchSucceeded = true
                
                let backup = Backup(workouts: tempWalks, events: tempEvents)
                
                let json = try JSONEncoder().encode(backup)
                return json
                
            } catch {
                return nil
            }
            
        }) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    guard let data = data else {
                        completion(fetchSucceeded ? .encodeFailed : .fetchFailed, nil)
                        return
                    }
                    completion(nil, data)
                case .failure(let error):
                    completion(.databaseError(error: error), nil)
                }
            }
        }
        
        
    }
    
    // MARK: - HealthKit
    
    /**
     Queries the uuids corresponding to HealthKit walks imported from or saved to AppleHealth and associated with walks saved in the app.
     - note: This function should only be used on the main thread
     */
    public static func queryExistingHealthUUIDs() -> [UUID] {
        threadSafeSyncReturn {
            return (try? dataStack.queryAttributes(
                From<Walk>()
                    .select(NSDictionary.self, .attribute(\._healthKitUUID))
                    .where(\._healthKitUUID != nil))
                        .compactMap { $0.first?.value as? UUID }
            ) ?? []
        }
    }
}
