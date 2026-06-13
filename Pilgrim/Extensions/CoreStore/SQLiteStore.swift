//
//  SQLiteStore.swift
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

import CoreData
import CoreStore

extension SQLiteStore {
    
    /**
     A function to determine the current `DataModelProtocol` of the `SQLiteStore` from a provided migration chain
     - parameter migrationChain: the migration chain used to check for the current model
     - returns: the current `DataModelProtocol` of the `SQLiteStore`; if nil it could not be determined or the storage does not exist yet
     */
    internal func currentORModel(from migrationChain: [DataModelProtocol.Type]) -> DataModelProtocol.Type? {
        return self.currentORModel(from: migrationChain, probeCount: nil)
    }

    /**
     Resolves the current model and reports how many models the probe loop materialized.
     - parameter probeCount: a sink incremented once per `isConfiguration` probe (launch profiling / tests)
     */
    internal func currentORModel(
        from migrationChain: [DataModelProtocol.Type],
        probeCount: UnsafeMutablePointer<Int>?
    ) -> DataModelProtocol.Type? {

        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: type(of: self).storeType,
            at: self.fileURL as URL,
            options: self.storeOptions
        ) else {
            return nil
        }

        return Self.matchModel(
            in: migrationChain,
            against: metadata,
            configuration: self.configuration,
            probeCount: probeCount
        )
    }

    /**
     Resolves the chain version whose model exactly matches the given store metadata.

     Probes the chain newest-first: an up-to-date store matches on the first probe instead of
     building ~11 older `NSManagedObjectModel`s on the way to the current one (the #42 launch win).

     Matching uses an **exact** entity-version-hash equality (`==` on `entityVersionHashesByName`),
     mirroring CoreStore's own `SchemaHistory.schema(for:)`. The shipped code used
     `isConfiguration(withName:compatibleWithStoreMetadata:)`, which returns `true` for any newer
     **superset** model whose shared entities still hash-match — so an older store would match a
     newer model. Under the original oldest-first order that was harmless (the exact version was
     probed first), but newest-first would pick the newer model and skip a migration step. Exact
     equality is order-independent: each chain version has a distinct full hash set
     (`ModelResolutionTests.test_chainSchemas_havePairwiseDistinctVersionHashes`), so exactly one
     version can match, and `ModelResolutionTests.test_detection_isIdentical_forBothProbeDirections`
     proves this resolves identically to the shipped oldest-first detection for every install state.
     The migration chain, mapping providers, and schema contents are untouched.
     - parameter migrationChain: the migration chain (oldest-first, as declared)
     - parameter metadata: the persistent store metadata to match against
     - parameter configuration: the store configuration name (unused by exact matching; kept for API symmetry)
     - parameter probeCount: optional sink incremented once per model probe (launch profiling / tests)
     - returns: the matching `DataModelProtocol.Type`, or nil if none match
     */
    internal static func matchModel(
        in migrationChain: [DataModelProtocol.Type],
        against metadata: [String: Any],
        configuration: String?,
        probeCount: UnsafeMutablePointer<Int>? = nil
    ) -> DataModelProtocol.Type? {

        guard let storeHashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] else {
            return nil
        }

        for type in migrationChain.reversed() {
            probeCount?.pointee += 1
            if type.schema.rawModel().entityVersionHashesByName == storeHashes {
                return type
            }
        }

        return nil
    }

}
