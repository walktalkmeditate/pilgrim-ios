import Foundation

/// Signal 5 of the invariance track, split into its own file so
/// `DossierSensesInvariance.swift` stays under the `file_length` gate after
/// the final-review fixes widened its doc comments. Behaviour is unchanged
/// by the move; the signal still ships dark behind `pendingFieldGate` and is
/// still dispatched from `DossierSenses.evaluateInvariant`.
extension DossierSensesInvariance {

    /// The walker deliberately set out carrying a word, on at least
    /// `minimumInvariantWalks` walks, and that word's thread is STILL
    /// steady across those same walks. They tried, on purpose, and nothing
    /// moved.
    ///
    /// SHIPS DARK behind `pendingFieldGate`. This is the most confronting
    /// line the app can produce; the engine and its tests exist so the
    /// judgement can be made on real history, not on a guess.
    ///
    /// `intentionWalks` is drawn from intention TEXT
    /// (`WalkSnapshotRow.intention`, via `DossierSenses.intentionLemmas` —
    /// the same scaffold-stripping helper `intentionLineage` already uses,
    /// so a filler verb never masquerades as a carried topic).
    /// `ThreadStore.salienceDirection` is drawn from the thread's
    /// APPEARANCES — a different, independently dated set. Neither is a
    /// subset of the other: a walker can name a word as intention on a
    /// walk that never comes up again in speech (no appearance that walk),
    /// and a thread can appear on walks where the word was never the
    /// stated intention at all.
    ///
    /// Reporting the raw intention-text count while judging steadiness over
    /// the FULL unfiltered thread would let the sentence (a) name a walk
    /// count the steadiness verdict never actually covers, and (b) let flat
    /// history on unrelated walks cancel out a real shift that happened
    /// exactly during the walks the intention was carried — "has not
    /// shifted SINCE" would have no temporal anchor for "since" to mean
    /// anything. So both the rendered N and the direction verdict are bound
    /// to the same evidence: walks where the intention was set on this
    /// lemma AND the thread has an appearance that walk, filtered down and
    /// judged in date order (appearances arrive pre-sorted from
    /// `ThreadStore.build`, and `filter` preserves that order).
    static func unarrivedIntention(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        var intentionWalks: [String: Set<UUID>] = [:]
        for snapshot in input.walkSnapshots {
            guard let intention = snapshot.intention, !intention.isEmpty else { continue }
            for lemma in DossierSenses.intentionLemmas(in: intention) {
                intentionWalks[lemma, default: []].insert(snapshot.walkUUID)
            }
        }

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            guard let carried = intentionWalks[thread.lemma] else { continue }

            let boundAppearances = thread.appearances.filter { carried.contains($0.walkUUID) }
            let boundWalks = Set(boundAppearances.map(\.walkUUID))
            guard boundWalks.count >= minimumInvariantWalks else { continue }

            let boundThread = WalkThread(
                lemma: thread.lemma, displayTerm: thread.displayTerm, appearances: boundAppearances
            )
            guard ThreadStore.salienceDirection(of: boundThread) == .steady else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' was set as an intention on \(boundWalks.count) walks; "
                    + "it has not shifted since.",
                lemma: thread.lemma
            )
        }
        return nil
    }
}
