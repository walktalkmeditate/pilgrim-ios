import Foundation

/// Small embedded lexicons for on-device linguistic markers. The absolutist
/// set is the 19-word dictionary from Al-Mosaiwi & Johnstone 2018 (Table 1,
/// open access) — verify verbatim against the paper before shipping. LIWC's
/// proprietary word lists must never be copied here.
enum MarkerLexicons {

    static let absolutist: Set<String> = [
        "absolutely", "all", "always", "complete", "completely", "constant",
        "constantly", "definitely", "entire", "ever", "every", "everyone",
        "everything", "full", "must", "never", "nothing", "totally", "whole"
    ]

    static let firstPersonSingular: Set<String> = ["i", "me", "my", "mine", "myself"]

    static let insight: Set<String> = [
        "realize", "realized", "realizing", "understand", "understood",
        "understanding", "notice", "noticed", "noticing", "aware", "awareness",
        "clarity", "insight", "learn", "learned", "learning", "recognize",
        "recognized", "sense", "sensed"
    ]

    static let causation: Set<String> = [
        "because", "cause", "caused", "causes", "effect", "hence", "since",
        "therefore", "thus", "reason", "reasons", "why", "consequently", "led"
    ]

    static let discrepancy: Set<String> = [
        "should", "would", "could", "ought", "need", "needed", "want",
        "wanted", "wish", "wished", "hope", "hoped", "rather", "instead"
    ]

    static let futureMarkers: Set<String> = [
        "will", "shall", "gonna", "tomorrow", "soon", "later", "ahead",
        "upcoming", "future", "plan", "plans", "planning"
    ]

    static let pastMarkers: Set<String> = [
        "was", "were", "did", "had", "ago", "yesterday", "remember",
        "remembered", "used", "back", "once", "before"
    ]

    /// Modal verbs are a STATE signal (design decision, modal-lean spec):
    /// they stay in this markers channel with per-word identity, and are
    /// explicitly excluded from the recurring-word TOPIC directive
    /// (`SpokenStoplist.scaffoldLemmas`) — a flat walk's "can ×57" is noise
    /// there, not a theme. Six families, each an ordered array (not a Set)
    /// so a dominant-word tie always resolves to the same word.
    ///
    /// "have to" (obligation) is a multi-word phrase and DEFERRED — this
    /// lexicon is single-token only.
    enum ModalFamily: String, CaseIterable {
        case possibility, obligation, counterfactual, tentative, intention, desire
    }

    static let modalFamilies: [ModalFamily: [String]] = [
        .possibility: ["can", "could"],
        .obligation: ["should", "must", "ought"],
        .counterfactual: ["would"],
        .tentative: ["might", "may"],
        .intention: ["will"],
        .desire: ["want", "need", "wish"]
    ]

    static let modalWords: Set<String> = Set(modalFamilies.values.flatMap { $0 })

    /// Every modal word belongs to exactly one family, so the search order
    /// never affects the result.
    static func modalFamily(of word: String) -> ModalFamily? {
        modalFamilies.first { $0.value.contains(word) }?.key
    }
}
