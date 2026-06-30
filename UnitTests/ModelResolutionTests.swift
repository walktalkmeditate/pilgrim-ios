import XCTest
import CoreData
import CoreStore
@testable import Pilgrim

/// U9: proves the newest-first `currentORModel` probe reversal is behaviour-preserving.
///
/// The reversal's risk is that a newer chain model could match a store written by an older one —
/// newest-first would then pick the newer model and silently skip a custom mapping step. U9
/// neutralises this two ways, both proven here:
///   1. Detection now uses **exact** `entityVersionHashesByName` equality (mirroring CoreStore's
///      own `SchemaHistory.schema(for:)`), so exactly one version matches a given store — the
///      chain hashes are pairwise distinct (`test_chainSchemas_havePairwiseDistinctVersionHashes`)
///      and every store resolves to its own version (`test_everyStore_resolvesToItsOwnVersion…`).
///   2. Even where the change *does* shift detection vs the old loose `isConfiguration` check,
///      DataManager's downstream `relevants` computation is identical
///      (`test_relevantsComputation_isIdentical…`), so the migration walk is untouched.
///
/// The rest confirm the win (up-to-date store → one probe → PilgrimV7) and that a real on-disk
/// older store (PilgrimV6) is still detected by the production `currentORModel`.
final class ModelResolutionTests: XCTestCase {

    private let chain = PilgrimV7.migrationChain

    // MARK: - Safety proof: pairwise-distinct version hashes

    func test_chainSchemas_havePairwiseDistinctVersionHashes() {
        var seen: [String: String] = [:]

        for type in chain {
            let hashes = type.schema.rawModel().entityVersionHashesByName
            let fingerprint = hashes
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.base64EncodedString())" }
                .joined(separator: "|")

            if let collidingVersion = seen[fingerprint] {
                XCTFail(
                    "Version-hash collision between \(collidingVersion) and \(type.identifier): "
                    + "newest-first probing could match the wrong model and skip a migration step."
                )
            }
            seen[fingerprint] = type.identifier
        }

        XCTAssertEqual(
            seen.count, chain.count,
            "all \(chain.count) chain schemas must have distinct entity-version-hash sets"
        )
    }

    // MARK: - Up-to-date store resolves on the first probe

    func test_upToDateStore_resolvesToPilgrimV7_onFirstProbe() {
        let metadata = Self.metadata(for: PilgrimV7.schema)

        var probeCount = 0
        let resolved = SQLiteStore.matchModel(
            in: chain,
            against: metadata,
            configuration: nil,
            probeCount: &probeCount
        )

        XCTAssertTrue(resolved == PilgrimV7.self, "an up-to-date store must resolve to PilgrimV7")
        XCTAssertEqual(probeCount, 1, "newest-first probing must match PilgrimV7 on the first probe")
    }

    // MARK: - Older store is still detected (V6 is the second-newest → second probe)

    func test_pilgrimV6Store_isStillDetected() {
        let metadata = Self.metadata(for: PilgrimV6.schema)

        var probeCount = 0
        let resolved = SQLiteStore.matchModel(
            in: chain,
            against: metadata,
            configuration: nil,
            probeCount: &probeCount
        )

        XCTAssertTrue(resolved == PilgrimV6.self, "a PilgrimV6 store must still resolve to PilgrimV6")
        XCTAssertEqual(probeCount, 2, "V6 is the second-newest version → matched on the second probe")
    }

    // MARK: - Every store resolves to its own version under newest-first matching

    /// The decisive safety proof for the newest-first reversal.
    ///
    /// `matchModel` uses **exact** `entityVersionHashesByName` equality — the same comparison
    /// CoreStore's own `SchemaHistory.schema(for:)` uses to find a store's source version before
    /// migrating it. So for every install state, `matchModel` resolves a store to exactly the
    /// version that wrote it, regardless of probe order. This is asserted for all 12 versions.
    ///
    /// (Aside, documented for U19: the *pre-U9* code probed oldest-first using
    /// `isConfiguration(withName:compatibleWithStoreMetadata:)`, a looser **subset** check —
    /// `test_isConfigurationCheck_isLoose_whichIsWhyExactMatchingWasRequired` proves that check
    /// matched some older stores to an even-older model, which newest-first could never use
    /// safely. That is why this unit switched to exact equality.)
    func test_everyStore_resolvesToItsOwnVersion_underNewestFirst() {
        for type in chain {
            let metadata = Self.metadata(for: type.schema)

            var probeCount = 0
            let resolved = SQLiteStore.matchModel(
                in: chain,
                against: metadata,
                configuration: nil,
                probeCount: &probeCount
            )

            XCTAssertTrue(
                resolved == type,
                "a \(type.identifier) store must resolve to \(type.identifier), "
                + "got \(resolved.map { $0.identifier } ?? "nil")"
            )
        }
    }

    /// Documents that the exact match agrees with CoreStore's own ground-truth detection.
    func test_matchModel_agreesWithCoreStoreSchemaForMetadata() {
        for type in chain {
            let metadata = Self.metadata(for: type.schema)
            let storeHashes = type.schema.rawModel().entityVersionHashesByName

            // CoreStore's ground truth: exact full-dictionary equality.
            let coreStoreMatch = chain.first { $0.schema.rawModel().entityVersionHashesByName == storeHashes }
            let ourMatch = SQLiteStore.matchModel(in: chain, against: metadata, configuration: nil)

            XCTAssertTrue(
                ourMatch == coreStoreMatch,
                "matchModel disagreed with CoreStore's exact detection for \(type.identifier)"
            )
        }
    }

    // MARK: - The production `currentORModel` against a real on-disk older store

    /// Exercises the actual shipped entry point (`SQLiteStore.currentORModel`) end-to-end against a
    /// real on-disk SQLite store written at the PilgrimV6 schema. This is the install-state that
    /// migrates on the next launch (`AE1`): the store must be detected as PilgrimV6 (not skipped,
    /// not mis-detected as current), so DataManager builds the correct migration `relevants`.
    /// Uses a raw `NSPersistentStoreCoordinator` to write the fixture — the repo's established
    /// on-disk-store pattern (`DeleteRuleVersionHashTests`).
    func test_currentORModel_detectsRealOnDiskV6Store() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("model-resolution-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("Fixture.sqlite")

        // Write a real SQLite store stamped with PilgrimV6's model hashes.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: PilgrimV6.schema.rawModel())
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: nil
        )

        // The production resolver must detect it as PilgrimV6, on the second probe (V7 then V6).
        let store = SQLiteStore(fileURL: storeURL)
        var probeCount = 0
        let detected = store.currentORModel(from: chain, probeCount: &probeCount)

        XCTAssertTrue(detected == PilgrimV6.self, "a real on-disk V6 store must be detected as PilgrimV6")
        XCTAssertEqual(probeCount, 2, "newest-first: V7 probed first (no match), then V6 (match)")
    }

    // MARK: - Downstream behaviour preservation (the migration-equivalence proof)

    /// The strongest guarantee: even where exact and loose detection DISAGREE on `currentVersion`,
    /// DataManager's downstream `relevants` / `destinationModel` computation produces an IDENTICAL
    /// result. Detection only gates whether the single `IntermediateDataModelProtocol`
    /// (OutRunV3to4) is included; for every store state both semantics yield the same destination
    /// model and the same intermediate set — so the actual migration walk is unchanged. This is
    /// why the probe-order + matching-semantic change is provably migration-neutral.
    func test_relevantsComputation_isIdentical_forExactAndLooseDetection() {
        for type in chain {
            let metadata = Self.metadata(for: type.schema)

            let exactDetected = SQLiteStore.matchModel(in: chain, against: metadata, configuration: nil)
            let looseDetected = Self.matchModelByConfiguration(in: chain, against: metadata)

            let exactRelevants = Self.computeRelevants(currentVersion: exactDetected)
            let looseRelevants = Self.computeRelevants(currentVersion: looseDetected)

            XCTAssertEqual(
                exactRelevants.map { $0.identifier },
                looseRelevants.map { $0.identifier },
                "relevants diverged for a \(type.identifier) store "
                + "(exact detected \(exactDetected.map { $0.identifier } ?? "nil"), "
                + "loose detected \(looseDetected.map { $0.identifier } ?? "nil"))"
            )
            XCTAssertEqual(
                exactRelevants.first?.identifier, PilgrimV7.identifier,
                "every store's destination model must be PilgrimV7"
            )
        }
    }

    /// Mirrors `DataManager.setup`'s `relevants` filter so the test can compare the downstream
    /// effect of a detection result without booting the full data stack.
    private static func computeRelevants(
        currentVersion: DataModelProtocol.Type?
    ) -> [DataModelProtocol.Type] {
        let dataModel: DataModelProtocol.Type = PilgrimV7.self
        return dataModel.migrationChain.filter { type in
            type == dataModel
                || (currentVersion != nil
                    ? type is IntermediateDataModelProtocol
                        && (type.isSuccessor(to: currentVersion!) || type == currentVersion)
                    : false)
        }
    }

    // MARK: - The looseness that forced exact matching (regression guard for the discovery)

    /// Proves the concrete reason this unit could NOT keep `isConfiguration` while reversing the
    /// probe order: the loose subset check matches some older stores to an EVEN-OLDER model. With
    /// oldest-first that was hidden (the exact version was probed before the looser one); with
    /// newest-first it would have been catastrophic (matching a newer model, skipping a migration).
    /// Switching to exact equality removes the looseness entirely — this test documents that the
    /// looseness was real, so a future "just use isConfiguration again" change is caught.
    func test_isConfigurationCheck_isLoose_whichIsWhyExactMatchingWasRequired() {
        // An OutRunV2 store's metadata is `isConfiguration`-compatible with OutRunV1's model
        // (subset match), even though it is NOT an exact hash match.
        let v2Metadata = Self.metadata(for: OutRunV2.schema)

        let looseOldestFirst = Self.matchModelByConfiguration(in: chain, against: v2Metadata)
        XCTAssertTrue(
            looseOldestFirst == OutRunV1.self,
            "the loose isConfiguration check is expected to mis-match an OutRunV2 store to OutRunV1"
        )

        let exact = SQLiteStore.matchModel(in: chain, against: v2Metadata, configuration: nil)
        XCTAssertTrue(exact == OutRunV2.self, "exact matching resolves the OutRunV2 store correctly")
    }

    // MARK: - Helpers

    private static func metadata(for schema: CoreStoreSchema) -> [String: Any] {
        return [NSStoreModelVersionHashesKey: schema.rawModel().entityVersionHashesByName]
    }

    /// The pre-U9 matching semantic: oldest-first probe using the loose
    /// `isConfiguration(withName:compatibleWithStoreMetadata:)` subset check.
    private static func matchModelByConfiguration(
        in chain: [DataModelProtocol.Type],
        against metadata: [String: Any]
    ) -> DataModelProtocol.Type? {
        for type in chain where type.schema.rawModel().isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        ) {
            return type
        }
        return nil
    }
}
