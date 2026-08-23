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
}
