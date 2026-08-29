import NaturalLanguage

/// Whether the on-device Natural Language models these tests depend on are
/// present for English. Computed once and cached: hosted CI runners
/// (macos-26, confirmed by direct observation — `NLTagger.requestAssets`
/// never calls back at all, not even slowly) have no path to obtain them,
/// while any developer machine or physical device that has ever primed them
/// has them permanently on disk.
///
/// Both schemes are required, not just `.lemma`.
/// `TranscriptNLP.contentLemmaMentions` enumerates by `.lexicalClass` to
/// decide what counts as content at all, and only then asks `.lemma` for the
/// canonical form. So `ThemeExtractor`, which filters to `[.noun]`, yields
/// nothing without the class model even on a fixture whose surface forms are
/// already canonical — `testRepeatedLemma_becomesTheme` failed on CI for
/// exactly that reason while a `.lemma`-only check judged the runner capable.
///
/// Tests whose assertions depend on real tagger output — rather than the
/// surface-form fallback `TranscriptNLP` degrades to when no model is present
/// — guard with `try XCTSkipUnless(NLAssetAvailability.lemmaAvailable, ...)`.
/// See `NLAssetWarmupTests` for the probe that reports which case is true.
enum NLAssetAvailability {
    static let lemmaAvailable: Bool = {
        let schemes = NLTagger.availableTagSchemes(for: .word, language: .english)
        return schemes.contains(.lemma) && schemes.contains(.lexicalClass)
    }()
}
