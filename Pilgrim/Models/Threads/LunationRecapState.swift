import Foundation

/// Persistence + eligibility for the lunation recap invitation. The acted
/// flag records "acted on", not "first opportunity" — pending
/// transcriptions don't cost the walker the month. Ephemeral by design:
/// loss on reinstall is accepted (unlike the released set, these are
/// bookkeeping, not walker decisions).
final class LunationRecapState {

    static let shared = LunationRecapState(defaults: .standard)

    static let firstCardShownKey = "threadsFirstCardShownAt"
    static let lastActedKey = "threadsRecapLastActedLunation"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var firstCardShownAt: Date? {
        guard let epoch = defaults.object(forKey: Self.firstCardShownKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    /// Set once, on the first per-walk card the walker ever sees — the card
    /// shows its work one walk at a time before any aggregate speaks.
    func markFirstCardShown(now: Date = Date()) {
        guard firstCardShownAt == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Self.firstCardShownKey)
    }

    var lastActedLunationIndex: Int? {
        defaults.object(forKey: Self.lastActedKey) as? Int
    }

    /// Monotonic: opening an older moon from Past recaps also marks it
    /// acted-on, and must never regress the index and resurrect an
    /// already-dismissed invitation.
    func markActedOn(_ lunation: Lunation) {
        defaults.set(max(lunation.index, lastActedLunationIndex ?? Int.min), forKey: Self.lastActedKey)
    }

    /// The lunation whose set moon may invite from this walk's summary, or
    /// nil. Re-evaluates on every qualifying post-boundary summary until the
    /// invitation is tapped or the next lunation closes.
    func invitation(forWalkDated walkDate: Date, now: Date = Date()) -> Lunation? {
        guard UserPreferences.threadsAfterWalks.value else { return nil }
        guard let firstShown = firstCardShownAt else { return nil }
        let closed = LunationCalendar.mostRecentClosed(asOf: now)
        guard closed.end > firstShown else { return nil }
        // An acted index beyond the current lunation can only come from a
        // forward-set clock (the manual smoke does exactly this) — ignore
        // it, so months of real invitations aren't silenced after the
        // clock returns.
        let currentIndex = LunationCalendar.lunation(containing: now).index
        let lastActed = lastActedLunationIndex.flatMap { $0 > currentIndex ? nil : $0 }
        guard closed.index > (lastActed ?? Int.min) else { return nil }
        guard walkDate >= closed.end else { return nil }
        return closed
    }

    /// Delete All Data hook — the first-card gate re-arms exactly as a
    /// reinstall would. Without this, a surviving firstCardShownAt
    /// resurrects pre-wipe moons as ghost Past-recap rows and turns the
    /// first post-wipe walk into a junk "no recorded words" invitation.
    func clear() {
        defaults.removeObject(forKey: Self.firstCardShownKey)
        defaults.removeObject(forKey: Self.lastActedKey)
    }
}
