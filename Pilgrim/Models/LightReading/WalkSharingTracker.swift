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
