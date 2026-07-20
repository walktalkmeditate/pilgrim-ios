import XCTest
@testable import Pilgrim

/// Bumping the shipped Whisper variant (`tiny` → `base`) must not strand
/// existing installs: the saved model path predates the variant bump, so
/// resolution has to reject it, and the sibling purge — which runs only
/// after the replacement model has downloaded and loaded — reclaims the
/// stale model's disk space without ever deleting the working model first.
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

    func testResolvedModelPath_relativePath_resolvesAgainstDocuments() throws {
        let relative = "\(suiteName)-relative/openai_whisper-base"
        let absolute = TranscriptionService.documentsDirectory.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: absolute, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: absolute.deletingLastPathComponent()) }
        defaults.set(relative, forKey: TranscriptionService.modelPathDefaultsKey)
        defaults.set("base", forKey: TranscriptionService.modelVariantDefaultsKey)

        let resolved = TranscriptionService.resolvedModelPath(defaults: defaults, variant: "base")

        XCTAssertEqual(resolved?.path, absolute.path,
                       "relative paths must survive container relocation by resolving against the current Documents")
    }

    func testRelativeModelPath_stripsDocumentsPrefix() {
        let url = TranscriptionService.documentsDirectory
            .appendingPathComponent("huggingface/models/openai_whisper-base")

        XCTAssertEqual(TranscriptionService.relativeModelPath(for: url),
                       "huggingface/models/openai_whisper-base")
    }

    func testPurgeStaleModels_removesSiblingVariantsOnly() throws {
        let baseDir = containerDir.appendingPathComponent("openai_whisper-base")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        TranscriptionService.purgeStaleModels(around: baseDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path),
                       "the stale tiny sibling must be deleted to reclaim disk space")
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDir.path),
                      "the freshly verified model must never be purged")
    }
}
