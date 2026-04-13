import Foundation

/// Persists the set of walks the user has shared so the Light Reading
/// card can be revealed only after the first Share tap for that walk —
/// and stay revealed on subsequent visits.
///
/// Storage: a single UserDefaults key (`sharedWalkUUIDs`) holding an
/// `[String]` of walk UUIDs. Using one key instead of one-per-walk
/// prevents UserDefaults from accumulating thousands of entries over
/// years of use — membership checks still run over a `Set<String>`
/// built from the stored array.
final class WalkSharingTracker {
    private let key = "sharedWalkUUIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns `true` if the user has tapped Share at least once for
    /// a walk with this UUID.
    func hasShared(walkUUID: String) -> Bool {
        sharedUUIDs.contains(walkUUID)
    }

    /// Records that the user tapped Share for this walk. Idempotent —
    /// calling this for an already-marked walk is a no-op.
    func markShared(walkUUID: String) {
        var uuids = sharedUUIDs
        uuids.insert(walkUUID)
        defaults.set(Array(uuids), forKey: key)
    }

    private var sharedUUIDs: Set<String> {
        Set(defaults.array(forKey: key) as? [String] ?? [])
    }
}

// MARK: - Historical backfill
//
// TODO(#backfill): Walks shared before this feature shipped have no entry in
// WalkSharingTracker, so their Light Reading card won't reveal on re-visit
// until the user taps a share action again.
//
// A launch-time backfill is not feasible here: ShareService stores cached
// shares as individual UserDefaults keys keyed by "share:<UUID>" with no
// central index, so enumerating them would require scanning the entire
// UserDefaults domain — fragile and potentially slow on large installs.
//
// The v1 behaviour: all four share paths (Goshuin, Etegami, Copy, ShareLink)
// now call onShare?(), so ANY share action on a historical walk will seed
// the tracker going forward. The gap only affects users who shared before
// this release AND do not share again — an acceptable V1 regression.
