import XCTest
import NaturalLanguage

/// A capability *probe*, not a gate. On a developer machine or physical
/// device that has ever primed these assets before (the normal case — they
/// persist on disk, not just for the life of one simulator boot),
/// `NLTagger.requestAssets` calls its completion handler immediately with no
/// network wait, so this test costs nothing there.
///
/// On the macos-26 hosted CI runner, direct observation showed the callback
/// simply never fires — not a slow download, an asset path that is
/// unavailable on that runner entirely. Waiting longer does not help, so
/// this probe waits briefly, then reports what it found and moves on
/// without failing either way. `.github/workflows/test.yml` runs it as its
/// own non-blocking step so a probe that can't reach the model never takes
/// `Build and Test` down with it.
///
/// The 27 tests across the lemma-dependent layer (`AttentionDirectives`
/// subject-shift/intentionEcho/recurringWord, `ThemeExtractor`,
/// `TranscriptNLP`, and friends) each guard themselves individually with
/// `try XCTSkipUnless(NLAssetAvailability.lemmaAvailable, ...)` and skip
/// when this probe finds no model — visible in the test summary as skips,
/// not silently swallowed as passes and not lied about as failures. The
/// device test harness remains the real gate for the lemma layer; CI can
/// only report honestly on whether it ran.
final class NLAssetWarmupTests: XCTestCase {

    func testProbeEnglishLemmaAssetAvailability() {
        let language = NLLanguage.english
        let schemes: [NLTagScheme] = [.lemma, .lexicalClass]

        let requested = expectation(description: "NLTagger.requestAssets returned for \(schemes)")
        requested.expectedFulfillmentCount = schemes.count

        for scheme in schemes {
            NLTagger.requestAssets(for: language, tagScheme: scheme) { _, _ in
                requested.fulfill()
            }
        }

        // Short and non-fatal on purpose: XCTWaiter.wait(for:timeout:), unlike
        // XCTestCase.wait(for:timeout:), does not record a failure on
        // timeout. Five wasted minutes per CI run is unacceptable now that
        // we know the callback can simply never come.
        let result = XCTWaiter.wait(for: [requested], timeout: 25)

        if NLAssetAvailability.lemmaAvailable {
            print("[NLAssetWarmup] English lemma model IS available (requestAssets wait: \(result)) — lemma-dependent tests will run.")
        } else {
            print("""
                [NLAssetWarmup] No English lemma model is available on this runner \
                (requestAssets wait: \(result)). The 27 lemma-dependent tests will \
                XCTSkip — CI cannot validate that layer here, the device harness is \
                the real gate for it.
                """)
        }
    }
}
