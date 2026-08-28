import XCTest
import NaturalLanguage

/// A fresh CI simulator ships with no on-device Natural Language model
/// assets. Until English `.lemma`/`.lexicalClass` are downloaded once,
/// `NLTagger.availableTagSchemes(for:language:)` reports no lemma support
/// and every lemma-dependent call in the app silently degrades to a
/// surface-form fallback — this is the entire Thought Threads lemma layer
/// (`AttentionDirectives.lemmatizableLanguage`, `subjectShift`,
/// `TranscriptNLP`, `ThemeExtractor`).
///
/// This class exists to fail alone, loudly, and first. `.github/workflows/
/// test.yml` runs it as its own `xcodebuild test` invocation ahead of the
/// main suite (`-only-testing:UnitTests/NLAssetWarmupTests`), then skips it
/// in the main run (`-skip-testing:`), so priming happens before a single
/// lemma-dependent test executes rather than racing test order or
/// parallelism. If priming fails, this is the one red test — not the 27
/// confusing downstream failures ("nil" != "Optional(en)") that a missing
/// lemma model otherwise produces.
///
/// On a developer machine that has ever primed these assets before (which
/// is the normal case — the assets persist on disk, not just for the
/// life of one simulator boot), `requestAssets` calls its completion
/// handler immediately with no network wait. The download cost is paid
/// once per fresh machine/simulator, not on every local test run.
final class NLAssetWarmupTests: XCTestCase {

    func testEnglishLemmaAndLexicalClassAssetsPrime() {
        let language = NLLanguage.english
        let schemes: [NLTagScheme] = [.lemma, .lexicalClass]

        let downloaded = expectation(description: "NL assets requested for \(schemes)")
        downloaded.expectedFulfillmentCount = schemes.count

        for scheme in schemes {
            _ = NLTagger.requestAssets(for: language, tagScheme: scheme) { result, error in
                XCTAssertNil(error, "NLTagger.requestAssets(for: .english, tagScheme: \(scheme)) errored: \(String(describing: error))")
                XCTAssertNotEqual(result, .error, "NLTagger.requestAssets(for: .english, tagScheme: \(scheme)) reported .error")
                downloaded.fulfill()
            }
        }

        // Real network download over the runner's connection, not a local
        // computation — generous on purpose.
        wait(for: [downloaded], timeout: 300)

        let available = NLTagger.availableTagSchemes(for: .word, language: language)
        XCTAssertTrue(available.contains(.lemma), """
            CI cannot validate the lemma layer: no NL lemma model is available for English \
            even after NLTagger.requestAssets completed. Every lemma-dependent test downstream \
            (AttentionDirectives subject-shift, intentionEcho, recurringWord, ThemeExtractor, \
            TranscriptNLP) will fail or silently degrade to surface-form matching from here — \
            this is a simulator/runner asset problem, not a code problem. Fix priming, don't \
            chase the downstream failures.
            """)
    }
}
