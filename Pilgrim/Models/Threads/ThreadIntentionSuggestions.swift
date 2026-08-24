import Foundation

/// Offers, never claims: a theme that recurred across multiple walks may be
/// deliberately walked with. Surfaced only as optional intention chips — and
/// because Seek seeds from the chosen intention, a thread carried into a
/// Seek steers the clearings. Quality of this surface is judged at the
/// field gate alongside the card's themes.
enum ThreadIntentionSuggestions {

    /// The human field gate passed 2026-08-24 (spec addendum: "Chips:
    /// cleared to ship") — chips render in IntentionSettingView from 1.12.0.
    /// The header ships as "Recurring"; a softer-variant copy pass is a
    /// tracked fast-follow, judged against real chip words.
    static let pendingFieldGate = false

    static let recurrenceWindow: TimeInterval = 30 * 86400
    static let minimumDistinctWalks = 2
    static let maxSuggestions = 2

    private static var memo: (changeCount: Int, releasedToken: Int, day: Date, suggestions: [String])?
    private static let memoLock = NSLock()

    /// Pure core (tested): threads → suggestion phrases. Two lemmas can
    /// share a display term (move/moving → "the move"), so phrases are
    /// deduped before the cap — the walker is never offered the same chip
    /// twice while a distinct one waits behind it.
    static func select(threads: [WalkThread], asOf: Date, limit: Int = maxSuggestions) -> [String] {
        var seen: Set<String> = []
        return Array(
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
                .map { "walk with '\($0.0)'" }
                .filter { seen.insert($0).inserted }
                .prefix(limit)
        )
    }

    /// Same shape as ThreadsDossierBuilder: the preference and the CoreStore
    /// walk index are read on the main actor, then the store read and thread
    /// aggregation run detached. The memo is keyed on the store's changeCount
    /// plus the day (suggestions are window-relative, so a new day can shift
    /// them without any store mutation); changeCount is captured BEFORE
    /// loadAll so a mid-read mutation leaves the memo stale and the next
    /// call rebuilds instead of absorbing the mutation unseen.
    @MainActor
    static func current(
        asOf: Date = Date(),
        store: TranscriptContextStore = .shared,
        releasedStore: ReleasedThreadsStore = .shared,
        walkIndex: [UUID: (walkUUID: UUID, date: Date)]? = nil
    ) async -> [String] {
        guard !pendingFieldGate else { return [] }
        guard UserPreferences.threadsAfterWalks.value else { return [] }
        // walkIndex is injectable for Task 8's wiring test; production
        // callers pass nil and read the live CoreStore index on the main actor.
        let walkIndex = walkIndex ?? DataManager.voiceRecordingWalkIndex()
        guard !walkIndex.isEmpty else { return [] }

        let day = Calendar.current.startOfDay(for: asOf)
        let preLoadChangeCount = store.changeCount
        let releasedToken = releasedStore.changeCount
        let released = releasedStore.releasedLemmas
        memoLock.lock()
        let cached = memo
        memoLock.unlock()
        if let cached, cached.changeCount == preLoadChangeCount,
           cached.releasedToken == releasedToken, cached.day == day {
            return cached.suggestions
        }

        return await Task.detached(priority: .userInitiated) {
            let threads = ThreadStore.build(contexts: store.loadAll(), walks: walkIndex, released: released)
            let suggestions = select(threads: threads, asOf: asOf)
            memoLock.lock()
            memo = (preLoadChangeCount, releasedToken, day, suggestions)
            memoLock.unlock()
            return suggestions
        }.value
    }
}
