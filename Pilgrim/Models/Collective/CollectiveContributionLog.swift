// Pilgrim/Models/Collective/CollectiveContributionLog.swift
import Foundation

/// Remembers which walks actually moved the collective counter.
///
/// The walk summary's collective line is a claim about one walk's past, so it
/// cannot be gated on the live contribution preference. A pilgrim who
/// contributes a walk and later turns the toggle off would watch the line
/// vanish from a walk that did move the counter, and one who turns it on
/// afterwards would see a line claiming a contribution that never happened.
///
/// Storage follows `WalkSharingTracker`: one UserDefaults key holding a
/// `[String]`, not a key per walk, so the domain does not accumulate thousands
/// of entries over years of use. Unlike that tracker this one is capped —
/// it gains an entry on every contributed walk for the life of the install.
final class CollectiveContributionLog {

    /// Roughly three years of walking every single day. Beyond it the oldest
    /// identifiers fall off and those summaries lose their line, which is the
    /// price of a UserDefaults value that cannot grow without limit. Newest
    /// wins because the journal is read from the recent end.
    static let capacity = 1_000

    private let key = "collectiveContributedWalkUUIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func wasContributed(walkUUID: String) -> Bool {
        contributedUUIDs.contains(walkUUID)
    }

    /// Idempotent, and deliberately so: a walk re-recorded after a retry keeps
    /// its original position rather than evicting an unrelated walk.
    func record(walkUUID: String) {
        var uuids = contributedUUIDs
        guard !uuids.contains(walkUUID) else { return }

        uuids.append(walkUUID)
        if uuids.count > Self.capacity {
            uuids.removeFirst(uuids.count - Self.capacity)
        }
        defaults.set(uuids, forKey: key)
    }

    /// Insertion-ordered, which is what makes the eviction above drop the
    /// oldest walk rather than an arbitrary one.
    private var contributedUUIDs: [String] {
        defaults.array(forKey: key) as? [String] ?? []
    }
}
