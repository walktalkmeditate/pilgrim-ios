// Pilgrim/Models/Collective/CollectiveContributionLog.swift
import Foundation

/// Remembers which walks actually moved the collective counter. The summary's line
/// is a claim about one walk's past, so it cannot read the live contribution
/// preference: toggling off would erase a true line, on would fabricate one.
final class CollectiveContributionLog {

    /// Roughly three years of daily walking. Past it the oldest identifiers fall off
    /// and those summaries lose their line — newest wins, as the journal reads recent-first.
    static let capacity = 1_000

    private let key = "collectiveContributedWalkUUIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func wasContributed(walkUUID: String) -> Bool {
        contributedUUIDs.contains(walkUUID)
    }

    /// Idempotent: a walk re-recorded after a retry keeps its original position rather than evicting an unrelated walk.
    func record(walkUUID: String) {
        var uuids = contributedUUIDs
        guard !uuids.contains(walkUUID) else { return }

        uuids.append(walkUUID)
        if uuids.count > Self.capacity {
            uuids.removeFirst(uuids.count - Self.capacity)
        }
        defaults.set(uuids, forKey: key)
    }

    /// Insertion-ordered, which is what makes the eviction above drop the oldest walk rather than an arbitrary one.
    private var contributedUUIDs: [String] {
        defaults.array(forKey: key) as? [String] ?? []
    }
}
