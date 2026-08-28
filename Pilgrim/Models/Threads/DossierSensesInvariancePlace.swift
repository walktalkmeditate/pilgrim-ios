import Foundation
import CoreLocation

/// Signal 4 of the `Unchanged:` block, split out of
/// `DossierSensesInvariance.swift` to keep that file under the `file_length`
/// gate — the same split `DossierSensesInvarianceIntention.swift` already
/// took for signal 5. Same type, same purity contract.
extension DossierSensesInvariance {

    /// The same theme spoken inside the same `DossierSenses.placeClusterRadius`
    /// cluster on every walk that actually CONTRIBUTED a qualifying route
    /// fix — an invariant tied to ground rather than to language. Reuses
    /// `DossierSenses.qualifies` so a poor-accuracy or stale-gap fix is
    /// excluded on the same hygiene terms as `placeResonance`: a
    /// 500m-accuracy fix would make any two points on earth look like the
    /// same place.
    ///
    /// BOUNDED BY `ThreadStore.recurrenceWindow`, both the evidence and the
    /// denominator, because that is the window the fixes themselves come
    /// from. `ThreadsDossierBuilder.resolveFixes` only ever resolves a route
    /// fix for an appearance whose recording instant falls inside the 30 days
    /// before this walk; every earlier appearance is unlocatable BY
    /// CONSTRUCTION, not by any fact about GPS. Counting the theme's entire
    /// unwindowed history as the denominator therefore rendered sentences
    /// like "on 3 of the 14 walks it appears in" for a theme spoken on
    /// fourteen walks at fourteen carefully logged places — an opening clause
    /// that vouches for every located utterance, over a set eleven of whose
    /// members were never offered to the locator at all. Windowing both sides
    /// is what `placeResonance` and `intentionLineage` already do; this
    /// follows them, and the rendered line names the window out loud.
    ///
    /// GATED ON THE MEASURED SET WITHIN THAT WINDOW, deliberately, not on
    /// every in-window walk (product decision, 2026-08-27): this app is used
    /// on rural pilgrimage routes where GPS coverage is uneven, and a full
    /// coverage requirement meant one dead-zone walk with no fix at all could
    /// permanently silence an otherwise genuinely place-locked theme — too
    /// conservative to ship. `minimumInvariantWalks` applies to
    /// `coordinatesByWalk.count` (distinct walks that contributed at least
    /// one qualifying fix), not to the in-window walk count: a theme on 10
    /// in-window walks with only 1 usable fix still stays silent — clustering
    /// over fewer than `minimumInvariantWalks` points is not evidence of
    /// anything — but a theme on 5 in-window walks with 3 usable fixes that
    /// cluster tightly may speak, naming exactly what was measured. DO NOT
    /// reinstate a full-coverage check here; that regression is the whole
    /// point of this paragraph.
    ///
    /// THE CLAIM IS SCOPED TO LOCATED UTTERANCES, not to whole walks. A walk
    /// enters `coordinatesByWalk` on its FIRST qualifying fix, but a theme
    /// can be spoken more than once on one walk, and the second utterance
    /// may have no fix at all (or a poor one) — so "spoken in the same place
    /// on all N walks" would vouch for an utterance nothing ever measured.
    /// Both variants therefore open with "Every time '_' was spoken with its
    /// location known", which is exactly the set `maxPairwiseSpread` judged,
    /// and the walk counts that follow describe the reach of that set rather
    /// than making a second, wider claim. The alternative — requiring every
    /// appearance on a counted walk to carry a qualifying fix — was rejected:
    /// it is *stricter* than the walk-level full-coverage check the product
    /// decision above deliberately removed, and would silence the signal for
    /// exactly the rural walkers that decision was made for.
    ///
    /// Two rendered variants, the same shape `fusedThemes` already sets for
    /// identical-vs-nested walk-sets: full coverage says "all N of its walks
    /// in the last 30 days"; partial coverage names BOTH counts — "M of its N
    /// walks in the last 30 days" — stating what was measured without
    /// implying anything about the unmeasured walks. We do not know where
    /// those were, only that we cannot say.
    ///
    /// Clustering is judged by SPREAD — the maximum pairwise distance
    /// across every qualifying coordinate — never by distance from an
    /// arbitrary anchor point such as the first coordinate encountered.
    /// Two points can each sit within `placeClusterRadius` of a shared
    /// anchor while sitting up to 2x that radius from each other; that is
    /// not "the same place" by any reading a walker would recognize, and
    /// an anchor-relative check would silently depend on appearance order
    /// (which fix happens to come first). Requiring every pair to sit
    /// within the radius of EACH OTHER is the stricter, order-independent
    /// reading, and mirrors the compactness `placeResonance.bestCluster`
    /// already measures via its own `spread`. Verified by haversine that
    /// anchor-relative clustering lets points ~260m apart pass a 150m gate.
    ///
    /// English-gated like `fusedThemes` — see `englishRecordings`.
    static func placeFrameLock(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let windowStart = input.walkStart.addingTimeInterval(-ThreadStore.recurrenceWindow)
        let english = englishRecordings(in: input)
        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) && isEnglishThroughout(thread, english: english) {
            let inWindow = thread.appearances.filter { appearance in
                guard let instant = input.recordingTimestamps[appearance.recordingUUID] else { return false }
                return instant >= windowStart && instant <= input.walkEnd
            }
            let windowWalks = Set(inWindow.map(\.walkUUID)).count

            var coordinatesByWalk: [UUID: [DossierSenses.Coordinate]] = [:]
            for appearance in inWindow {
                guard let fix = input.fixes[appearance.recordingUUID],
                      DossierSenses.qualifies(fix) else { continue }
                coordinatesByWalk[appearance.walkUUID, default: []].append(fix.coordinate)
            }
            let measuredWalks = coordinatesByWalk.count
            guard measuredWalks >= minimumInvariantWalks else { continue }

            let coordinates = coordinatesByWalk.values.flatMap { $0 }
            guard maxPairwiseSpread(coordinates) <= DossierSenses.placeClusterRadius else { continue }

            let opening = "Every time '\(thread.displayTerm)' was spoken with its location known, "
                + "it was in the same place — on "
            guard measuredWalks < windowWalks else {
                return DossierSenses.SenseLine(
                    text: opening + "all \(windowWalks) of its walks in the last 30 days.",
                    lemma: thread.lemma
                )
            }

            return DossierSenses.SenseLine(
                text: opening + "\(measuredWalks) of its \(windowWalks) walks in the last 30 days.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// The greatest distance between any two coordinates in the set —
    /// order-independent, so which fix was recorded "first" cannot change
    /// the answer. Mirrors the `spread` computation in
    /// `DossierSenses.bestCluster`, minus the seed search: the coverage gate
    /// above already fixes the one candidate set this function is asked to
    /// judge, so there is nothing to search over.
    private static func maxPairwiseSpread(_ coordinates: [DossierSenses.Coordinate]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }
        var spread: CLLocationDistance = 0
        for i in 0..<(coordinates.count - 1) {
            for j in (i + 1)..<coordinates.count {
                spread = max(spread, DossierSenses.distance(coordinates[i], coordinates[j]))
            }
        }
        return spread
    }
}
