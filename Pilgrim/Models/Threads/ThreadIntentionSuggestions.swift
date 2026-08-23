import Foundation

/// Offers, never claims: a theme that recurred across multiple walks may be
/// deliberately walked with. Surfaced only as optional intention chips — and
/// because Seek seeds from the chosen intention, a thread carried into a
/// Seek steers the clearings. Quality of this surface is judged at the
/// field gate alongside the card's themes.
enum ThreadIntentionSuggestions {

    static let recurrenceWindow: TimeInterval = 30 * 86400
    static let minimumDistinctWalks = 2
    static let maxSuggestions = 2

    /// Pure core (tested): threads → suggestion phrases.
    static func select(threads: [WalkThread], asOf: Date, limit: Int = maxSuggestions) -> [String] {
        threads
            .compactMap { thread -> (String, Int)? in
                let windowStart = asOf.addingTimeInterval(-recurrenceWindow)
                let walks = Set(thread.appearances
                    .filter { $0.date >= windowStart && $0.date <= asOf }
                    .map(\.walkUUID))
                guard walks.count >= minimumDistinctWalks else { return nil }
                return (thread.displayTerm, walks.count)
            }
            .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
            .prefix(limit)
            .map { "walk with '\($0.0)'" }
    }

    @MainActor
    static func current(asOf: Date = Date(), store: TranscriptContextStore = .shared) -> [String] {
        guard UserPreferences.threadsAfterWalks.value else { return [] }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        guard !walkIndex.isEmpty else { return [] }
        let threads = ThreadStore.build(contexts: store.loadAll(), walks: walkIndex)
        return select(threads: threads, asOf: asOf)
    }
}
