import XCTest
@testable import Pilgrim

/// Bumping the shipped Whisper variant (`tiny` → `base`) must not strand
/// existing installs: the saved model path predates the variant bump, so
/// resolution has to reject it and purge has to reclaim the stale model's
/// disk space before the new variant downloads.
final class TranscriptionServiceModelVariantTests: XCTestCase {

    private let suiteName = "TranscriptionServiceModelVariantTests"
    private var defaults: UserDefaults!
    private var containerDir: URL!
    private var modelDir: URL!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        containerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suiteName)-\(UUID().uuidString)")
        modelDir = containerDir.appendingPathComponent("openai_whisper-tiny")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: containerDir)
    }

    private func saveModel(variant: String?) {
        defaults.set(modelDir.path, forKey: TranscriptionService.modelPathDefaultsKey)
        if let variant {
            defaults.set(variant, forKey: TranscriptionService.modelVariantDefaultsKey)
        }
    }

    func testShippedVariant_isBase() {
        XCTAssertEqual(TranscriptionService.modelVariant, "base")
    }

    func testResolvedModelPath_matchingVariant_returnsSavedPath() {
        saveModel(variant: "base")

        let resolved = TranscriptionService.resolvedModelPath(defaults: defaults, variant: "base")

        XCTAssertEqual(resolved?.path, modelDir.path)
    }

    func testResolvedModelPath_legacyPathWithoutVariantKey_isNil() {
        saveModel(variant: nil)

        let resolved = TranscriptionService.resolvedModelPath(defaults: defaults, variant: "base")

        XCTAssertNil(resolved, "a pre-bump install's saved path must not satisfy the new variant")
    }

    func testResolvedModelPath_differentVariant_isNil() {
        saveModel(variant: "tiny")

        let resolved = TranscriptionService.resolvedModelPath(defaults: defaults, variant: "base")

        XCTAssertNil(resolved, "a model saved for another variant must not be reused")
    }

    func testResolvedModelPath_missingFolder_isNil() throws {
        saveModel(variant: "base")
        try FileManager.default.removeItem(at: modelDir)

        let resolved = TranscriptionService.resolvedModelPath(defaults: defaults, variant: "base")

        XCTAssertNil(resolved)
    }

    func testPurgeStaleModel_legacyModel_removesFolderAndKeys() {
        saveModel(variant: nil)

        TranscriptionService.purgeStaleModel(defaults: defaults, variant: "base")

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path),
                       "the stale model folder must be deleted to reclaim disk space")
        XCTAssertNil(defaults.string(forKey: TranscriptionService.modelPathDefaultsKey))
        XCTAssertNil(defaults.string(forKey: TranscriptionService.modelVariantDefaultsKey))
    }

    func testPurgeStaleModel_currentVariant_keepsModel() {
        saveModel(variant: "base")

        TranscriptionService.purgeStaleModel(defaults: defaults, variant: "base")

        XCTAssertTrue(FileManager.default.fileExists(atPath: modelDir.path))
        XCTAssertEqual(defaults.string(forKey: TranscriptionService.modelPathDefaultsKey), modelDir.path)
        XCTAssertEqual(defaults.string(forKey: TranscriptionService.modelVariantDefaultsKey), "base")
    }
}
