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

    // MARK: - Dossier Senses

    /// Nearest route fix for one recording instant: a ±90 s timestamp-
    /// predicate query with a fetch limit — never a full `walk.routeData`
    /// materialization (spec: bounded fetch; the samples table is the
    /// store's largest). 240 caps the read: ~1 Hz logging yields ≤181
    /// samples inside ±90 s, so the ascending-order clip never bites in
    /// practice. Callable off-main via `threadSafeSyncReturn`, matching
    /// `queryExistingHealthUUIDs` — ThreadsDossierBuilder resolves fixes
    /// lazily from its detached build.
    public static func routeFixNear(timestamp: Date) -> DossierSenses.RouteFix? {
        threadSafeSyncReturn {
            let windowStart = timestamp.addingTimeInterval(-DossierSenses.hygieneMaxGap)
            let windowEnd = timestamp.addingTimeInterval(DossierSenses.hygieneMaxGap)
            guard let rows = try? dataStack.queryAttributes(
                From<RouteDataSample>()
                    .select(
                        NSDictionary.self,
                        .attribute(\._timestamp),
                        .attribute(\._latitude),
                        .attribute(\._longitude),
                        .attribute(\._horizontalAccuracy)
                    )
                    .where(\._timestamp >= windowStart && \._timestamp <= windowEnd)
                    .orderBy(.ascending(\._timestamp))
                    .tweak { $0.fetchLimit = 240 }
            ) else { return nil }
            return rows
                .compactMap { row -> DossierSenses.RouteFix? in
                    guard let sampleTime = row["timestamp"] as? Date,
                          let latitude = row["latitude"] as? Double,
                          let longitude = row["longitude"] as? Double,
                          let accuracy = row["horizontalAccuracy"] as? Double else { return nil }
                    return DossierSenses.RouteFix(
                        coordinate: DossierSenses.Coordinate(latitude: latitude, longitude: longitude),
                        horizontalAccuracy: accuracy,
                        gapSeconds: abs(sampleTime.timeIntervalSince(timestamp))
                    )
                }
                .min { ($0.gapSeconds, $0.horizontalAccuracy) < ($1.gapSeconds, $1.horizontalAccuracy) }
        }
    }

    /// One row per walk in range — intention (`comment`), stored weather,
    /// start date — one bounded fetch serving intention lineage, weather
    /// weave, and the moon line's walk counts.
    @MainActor
    public static func walkSensesSnapshot(from: Date, to: Date) -> [DossierSenses.WalkSnapshotRow] {
        guard let rows = try? dataStack.queryAttributes(
            From<Walk>()
                .select(
                    NSDictionary.self,
                    .attribute(\._uuid),
                    .attribute(\._startDate),
                    .attribute(\._comment),
                    .attribute(\._weatherCondition)
                )
                .where(\._startDate >= from && \._startDate <= to)
                .orderBy(.ascending(\._startDate))
        ) else { return [] }
        return rows.compactMap { row in
            guard let uuid = rowUUID(row["id"]),
                  let start = row["startDate"] as? Date else { return nil }
            return DossierSenses.WalkSnapshotRow(
                walkUUID: uuid,
                startDate: start,
                intention: row["comment"] as? String,
                weatherCondition: row["weatherCondition"] as? String
            )
        }
    }
}
