import NaturalLanguage

/// Whether the on-device Natural Language lemma model for English is present
/// on this machine. Computed once and cached: hosted CI runners (macos-26,
/// confirmed by direct observation) have no path to obtain this asset within
/// a CI-appropriate time budget, while any developer machine or physical
/// device that has ever primed it has it permanently on disk.
///
/// Tests whose assertions depend on real lemma output (as opposed to the
/// surface-form fallback `TranscriptNLP` and friends use when no model is
/// present) guard themselves with `try XCTSkipUnless(NLAssetAvailability.lemmaAvailable, ...)`
/// rather than asserting through a model that may not exist on the runner —
/// see `NLAssetWarmupTests` for the probe that surfaces which case is true.
enum NLAssetAvailability {
    static let lemmaAvailable: Bool = {
        NLTagger.availableTagSchemes(for: .word, language: .english).contains(.lemma)
    }()
}
