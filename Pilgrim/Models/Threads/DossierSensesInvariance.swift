import Foundation
import CoreLocation

/// Invariance track for the dossier's `Unchanged:` block — the mirror of
/// `Noticed:`. Where the senses report what was distinctive about THIS
/// walk, these report what has never moved across all of them.
///
/// Binding purity contract, identical to `DossierSenses`: no DataManager,
/// no CoreStore, no singleton access, and `Date()` is never called here —
/// time arrives as data. Every line stays traceable to enumerable,
/// deterministic inputs.
///
/// Why invariance at all: escaping a bad problem framing means noticing
/// what stayed the same across your failed attempts and changing THAT
/// (Kaplan & Simon 1990). Nobody keeps that record about themselves.
/// Thought Threads is that record.
enum DossierSensesInvariance {

    /// Signal 5 (unarrived intention) ships dark. It is the most
    /// confronting line the app can produce — it says, in effect, that the
    /// walker deliberately tried and nothing moved. Engine and tests ship;
    /// the flag flips only after the field gate judges it on real history.
    /// Mirrors `ThreadIntentionSuggestions.pendingFieldGate`.
    static let pendingFieldGate = true

    /// Every invariant needs at least this many walks before it may speak.
    /// Below it, a "pattern" is noise wearing a pattern's clothes.
    static let minimumInvariantWalks = 3

    /// Coefficient-of-variation ceiling for calling a marker profile flat.
    static let markerFlatnessCeiling = 0.20

    /// NLTagger sentiment spans -1...1, so a theme whose mean sits near
    /// zero would make raw CV explode. Shift into 0...2 before dividing.
    static let sentimentShift = 1.0
}

extension DossierSenses {

    /// Declaration order IS the spec's binding priority order — reordering
    /// cases reorders the block, exactly as with `Sense`.
    enum Invariant: CaseIterable {
        case fusedThemes, unmovedReturn, frameConstancy, placeFrameLock, unarrivedIntention
    }

    /// `evaluate` is a test seam, same style as `lines(input:evaluate:)`.
    ///
    /// SILENT UNTIL THE BACKFILL SWEEP HAS FINISHED. Every invariant is a
    /// coverage claim over the walker's whole record — "never apart", "each
    /// time", "every walk". `ThreadsBackfill` is battery-gated and
    /// single-flight, so a partly-analyzed record is an ordinary state, not
    /// a theoretical one: a walker who imports 40 walks and has had 6
    /// analyzed would otherwise be told "Every walk where 'grief' appears is
    /// obligation-dominant" on the strength of 3 walks out of 40 —
    /// `frameConstancy`'s whole "full coverage is the price of the word
    /// every" argument evaporating silently, because the pool it is complete
    /// over is itself incomplete. `ThreadsDossierFormatter` already gates
    /// every one of its weaker history claims (thread origin dates, `Quiet
    /// this walk`) on the same flag; the strongest claim in the app cannot
    /// be gated more loosely than the weakest.
    static func invarianceLines(
        input: Input,
        evaluate: (Invariant, Input, Set<String>) -> SenseLine? = {
            DossierSenses.evaluateInvariant($0, input: $1, suppressed: $2)
        }
    ) -> [String] {
        guard input.backfillComplete else { return [] }
        var used = Set<String>()
        var lines: [String] = []
        for invariant in Invariant.allCases {
            guard lines.count < lineCap else { break }
            guard let line = evaluate(invariant, input, used) else { continue }
            if let lemma = line.lemma {
                guard !used.contains(lemma) else { continue }
                used.insert(lemma)
            }
            lines.append(line.text)
        }
        return lines
    }

    static func evaluateInvariant(
        _ invariant: Invariant, input: Input, suppressed: Set<String>
    ) -> SenseLine? {
        switch invariant {
        case .fusedThemes:
            return DossierSensesInvariance.fusedThemes(input: input, suppressed: suppressed)
        case .unmovedReturn:
            return DossierSensesInvariance.unmovedReturn(input: input, suppressed: suppressed)
        case .frameConstancy:
            return DossierSensesInvariance.frameConstancy(input: input, suppressed: suppressed)
        case .placeFrameLock:
            return DossierSensesInvariance.placeFrameLock(input: input, suppressed: suppressed)
        case .unarrivedIntention:
            guard !DossierSensesInvariance.pendingFieldGate else { return nil }
            return DossierSensesInvariance.unarrivedIntention(input: input, suppressed: suppressed)
        }
    }
}

extension DossierSensesInvariance {

    /// Two themes whose walk-sets are identical, or where one nests wholly
    /// inside the other, across at least `minimumInvariantWalks` walks.
    ///
    /// This is a grouping the walker performed pre-categorically — they
    /// gathered two things together without ever deciding to, which is
    /// exactly the move that precedes forming a category. Partial overlap
    /// is NOT fusion: two themes sharing some walks is ordinary, and
    /// reporting it would be the Goodman error (everything resembles
    /// everything if you pick the properties afterwards).
    ///
    /// Identical and strictly-nested walk-sets are rendered differently:
    /// "never apart" is a true, symmetric claim only when the sets are
    /// equal. When one theme's walks are a strict subset of the other's,
    /// the superset theme has walks the subset theme took no part in, so
    /// the claim must be anchored — and worded — on the subset theme alone.
    /// That is also why `lemma` is always the subset theme's: `best.subset`
    /// on a strict nest, either theme when the sets are equal.
    ///
    /// The identical-set wording says "in the same N walks", never "in N of
    /// N walks": on this branch `shared == outer` by construction, so the
    /// denominator has no second quantity to contrast with and a walker
    /// reads "3 of 3" as "all of your walks" — which is a claim about their
    /// whole history that neither theme's walk-set supports. The nested
    /// branch keeps its two counts because there they genuinely differ.
    ///
    /// Deterministic: threads arrive lemma-sorted from `ThreadStore.build`,
    /// and only a STRICTLY larger shared-walk count replaces the best pair.
    static func fusedThemes(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let candidates = input.threads
            .filter { !suppressed.contains($0.lemma) }
            .map { (thread: $0, walks: Set($0.appearances.map(\.walkUUID))) }
            .filter { $0.walks.count >= minimumInvariantWalks }

        guard candidates.count >= 2 else { return nil }

        var best: (subset: WalkThread, superset: WalkThread, shared: Int, outer: Int)?
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                let (first, second) = (candidates[i], candidates[j])
                let firstIsSubset = first.walks.isSubset(of: second.walks)
                let secondIsSubset = second.walks.isSubset(of: first.walks)
                guard firstIsSubset || secondIsSubset else { continue }
                let shared = first.walks.intersection(second.walks).count
                let outer = max(first.walks.count, second.walks.count)
                guard best == nil || shared > best!.shared else { continue }
                best = firstIsSubset
                    ? (first.thread, second.thread, shared, outer)
                    : (second.thread, first.thread, shared, outer)
            }
        }

        guard let best else { return nil }

        guard best.shared < best.outer else {
            return DossierSenses.SenseLine(
                text: "'\(best.subset.displayTerm)' and '\(best.superset.displayTerm)' have appeared in "
                    + "the same \(best.shared) walks, never apart.",
                lemma: best.subset.lemma
            )
        }

        return DossierSenses.SenseLine(
            text: "'\(best.subset.displayTerm)' has appeared in \(best.shared) walks, always alongside "
                + "'\(best.superset.displayTerm)' — which walked \(best.outer) in all.",
            lemma: best.subset.lemma
        )
    }
}

extension DossierSensesInvariance {

    /// A theme that recurs with steady salience AND a flat marker profile:
    /// it has come back, and every time it sounds the same. That sameness
    /// across returns is the invariant — the thing that did not budge while
    /// the walker kept working at it.
    ///
    /// Appearances below `densityFloorWords` are EXCLUDED, never counted as
    /// flat: a short recording is not evidence of sameness, it is absence
    /// of evidence. At least `minimumInvariantWalks` must clear the floor —
    /// counted by distinct WALK, not by recording, mirroring `fusedThemes`
    /// and `ThreadsDossierFormatter.modalBaselineFloorWalks`: a walker who
    /// talks about the same thing three times on one walk isn't three
    /// returns, and the reported walk count must match the walks the
    /// flatness claim actually has evidence for — never a bare appearance
    /// count, which would let an unevidenced short recording inflate the
    /// "each time" the line claims to speak for.
    ///
    /// FLATNESS IS MEASURED PER WALK, not per recording. The rendered claim
    /// is walk-scoped ("returned across N walks; it sounds the same each
    /// time"), so the coefficient of variation must run over one value per
    /// walk — each walk's mean marker ratio — and never over the raw
    /// recordings. A recording-weighted CV lets a walk that carried eight
    /// recordings outvote two walks that carried one each: eight
    /// near-identical appearances on walk A drag the spread down until walks
    /// B and C differing by 2x still reads as flat. That is the same
    /// per-walk aggregation `frameConstancy` already performs on modal
    /// counts, and the same "bind the verdict to the evidence the sentence
    /// names" rule `unarrivedIntention` follows. Grouping first also means
    /// the walk count the line reports and the value count `isFlat` judges
    /// are the same number by construction, not by coincidence.
    static func unmovedReturn(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let byRecording = Dictionary(
            input.historicalContexts.map { ($0.recordingUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            guard ThreadStore.salienceDirection(of: thread) == .steady else { continue }

            let qualifying = thread.appearances.compactMap { appearance -> (walkUUID: UUID, markers: MarkerPack)? in
                guard let markers = byRecording[appearance.recordingUUID]?.markers,
                      markers.wordCount >= ThreadsDossierFormatter.densityFloorWords else { return nil }
                return (appearance.walkUUID, markers)
            }
            guard qualifying.allSatisfy({ $0.markers.sentiment != nil }) else { continue }
            // Sorted by UUID string only so the arithmetic is bit-identical
            // run to run; CV itself is order-independent.
            let packsByWalk = Dictionary(grouping: qualifying, by: \.walkUUID)
                .sorted { $0.key.uuidString < $1.key.uuidString }
                .map { $0.value.map(\.markers) }
            guard packsByWalk.count >= minimumInvariantWalks else { continue }

            let absolutist = packsByWalk.map { average($0.map { Double($0.absolutistCount) / Double($0.wordCount) }) }
            let firstPerson = packsByWalk.map { average($0.map { Double($0.firstPersonCount) / Double($0.wordCount) }) }
            let sentiment = packsByWalk.map { average($0.map { ($0.sentiment ?? 0) + sentimentShift }) }

            guard isFlat(absolutist), isFlat(firstPerson), isFlat(sentiment) else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has returned across \(packsByWalk.count) walks; "
                    + "it sounds the same each time.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// Coefficient of variation at or under the flatness ceiling. A zero or
    /// negative mean cannot be judged this way, so it is treated as not
    /// flat rather than dividing by it.
    static func isFlat(_ values: [Double]) -> Bool {
        guard values.count >= 2 else { return false }
        let mean = average(values)
        guard mean > 0 else { return false }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (variance.squareRoot() / mean) <= markerFlatnessCeiling
    }

    /// Arithmetic mean. Zero for an empty slice, which no caller here can
    /// produce — `Dictionary(grouping:)` never yields an empty group.
    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

extension DossierSensesInvariance {

    /// One modal family dominant in EVERY walk where the theme appears.
    /// Modals name the shape of the frame the walker was thinking inside —
    /// obligation constrains, counterfactual replays alternatives,
    /// possibility and tentative stay open. The same family every time is
    /// a frame that never varied.
    ///
    /// Grouped and gated by distinct WALK, not by qualifying recording,
    /// mirroring `fusedThemes` and `unmovedReturn`: a theme argued in three
    /// bursts on one walk is one data point about one frame, not three.
    /// When a walk carries more than one recording, their modal counts are
    /// SUMMED into a single per-walk total before a dominant family is
    /// picked — the same move `ThreadsDossierFormatter.modalLeanSummary`
    /// makes for naming today's walk's dominant family — rather than
    /// letting one recording's dominance silently stand for the walk, or
    /// resolving a same-walk disagreement some other, unprincipled way.
    ///
    /// The rendered line claims "every walk". That claim is only true if
    /// EVERY walk where the theme appears has a dominant family — so a
    /// walk with no modal evidence (its only recording(s) have `markers ==
    /// nil`, i.e. non-English, or an empty/unmapped `modalCounts`) is not
    /// silently dropped from the pool the way `unmovedReturn` drops
    /// sub-floor recordings. Dropping it here would let three walks that
    /// happen to agree outvote a fourth the line never looked at, while
    /// still claiming to speak for it. Instead a single uncovered walk
    /// holds the whole signal silent — full coverage is the price of the
    /// word "every". Silence is the correct default; see the type's doc
    /// comment.
    ///
    /// Per-walk dominance is a MODE, not a majority — the same fix PR #71
    /// applied to weatherWeave to kill the cloud tautologies. A family can
    /// dominate with 40% of the modals as long as nothing beats it.
    /// Deterministic ties: `ModalFamily.allCases` is declaration-ordered
    /// and only a STRICTLY greater count replaces the running best.
    static func frameConstancy(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let byRecording = Dictionary(
            input.historicalContexts.map { ($0.recordingUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            let allWalks = Set(thread.appearances.map(\.walkUUID))
            guard allWalks.count >= minimumInvariantWalks else { continue }

            var modalsByWalk: [UUID: [String: Int]] = [:]
            for appearance in thread.appearances {
                guard let modals = byRecording[appearance.recordingUUID]?.markers?.modalCounts,
                      !modals.isEmpty else { continue }
                modalsByWalk[appearance.walkUUID, default: [:]].merge(modals, uniquingKeysWith: +)
            }

            let dominantFamilies = allWalks.compactMap { modalsByWalk[$0].flatMap(dominantModalFamily) }
            guard dominantFamilies.count == allWalks.count,
                  let first = dominantFamilies.first,
                  dominantFamilies.allSatisfy({ $0 == first }) else { continue }

            return DossierSenses.SenseLine(
                text: "Every walk where '\(thread.displayTerm)' appears is "
                    + "\(first.rawValue)-dominant.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// The dominant `ModalFamily` for one walk's summed modal counts, or
    /// nil if none of the words present map to a known family. A mode over
    /// family totals, not a majority share — see `frameConstancy`.
    private static func dominantModalFamily(in modals: [String: Int]) -> MarkerLexicons.ModalFamily? {
        var totals: [MarkerLexicons.ModalFamily: Int] = [:]
        for (word, count) in modals {
            guard let family = MarkerLexicons.modalFamily(of: word) else { continue }
            totals[family, default: 0] += count
        }
        var best: (family: MarkerLexicons.ModalFamily, count: Int)?
        for family in MarkerLexicons.ModalFamily.allCases {
            let count = totals[family] ?? 0
            guard count > 0, best == nil || count > best!.count else { continue }
            best = (family, count)
        }
        return best?.family
    }
}

extension DossierSensesInvariance {

    /// The same theme spoken inside the same `DossierSenses.placeClusterRadius`
    /// cluster on every walk that actually CONTRIBUTED a qualifying route
    /// fix — an invariant tied to ground rather than to language. Reuses
    /// `DossierSenses.qualifies` so a poor-accuracy or stale-gap fix is
    /// excluded on the same hygiene terms as `placeResonance`: a
    /// 500m-accuracy fix would make any two points on earth look like the
    /// same place.
    ///
    /// GATED ON THE MEASURED SET, deliberately, not on the theme's full
    /// appearance history (product decision, 2026-08-27): this app is used
    /// on rural pilgrimage routes where GPS coverage is uneven, and a full
    /// coverage requirement meant one dead-zone walk with no fix at all
    /// could permanently silence an otherwise genuinely place-locked theme
    /// — too conservative to ship. `minimumInvariantWalks` now applies to
    /// `coordinatesByWalk.count` (distinct walks that contributed at least
    /// one qualifying fix), not `allWalks.count` (every walk the theme
    /// appears on): a theme in 10 walks with only 1 usable fix still stays
    /// silent — clustering over fewer than `minimumInvariantWalks` points
    /// is not evidence of anything — but a theme in 5 walks with 3 usable
    /// fixes that cluster tightly may now speak, naming exactly what was
    /// measured. DO NOT reinstate the `coordinatesByWalk.count ==
    /// allWalks.count` check this replaced; that regression is the whole
    /// point of this comment.
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
    /// identical-vs-nested walk-sets: full coverage says "on all N walks it
    /// appears in"; partial coverage names BOTH counts — "on M of the N
    /// walks it appears in" — stating what was measured without implying
    /// anything about the unmeasured walks. We do not know where those were,
    /// only that we cannot say.
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
    /// already measures via its own `spread`. UNCHANGED by the coverage
    /// relaxation above — verified by haversine that anchor-relative
    /// clustering lets points ~260m apart pass a 150m gate.
    static func placeFrameLock(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        for thread in input.threads.sorted(by: { $0.lemma < $1.lemma })
        where !suppressed.contains(thread.lemma) {
            let allWalks = Set(thread.appearances.map(\.walkUUID))

            var coordinatesByWalk: [UUID: [DossierSenses.Coordinate]] = [:]
            for appearance in thread.appearances {
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
            guard measuredWalks < allWalks.count else {
                return DossierSenses.SenseLine(
                    text: opening + "all \(allWalks.count) walks it appears in.",
                    lemma: thread.lemma
                )
            }

            return DossierSenses.SenseLine(
                text: opening + "\(measuredWalks) of the \(allWalks.count) walks it appears in.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// The greatest distance between any two coordinates in the set —
    /// order-independent, so which fix was recorded "first" cannot change
    /// the answer. Mirrors the `spread` computation in
    /// `DossierSenses.bestCluster`, minus the seed search: full coverage
    /// above already fixes the one candidate set this function is asked
    /// to judge, so there is nothing to search over.
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
