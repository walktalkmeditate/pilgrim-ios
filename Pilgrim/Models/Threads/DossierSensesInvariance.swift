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
    /// CV is the right instrument for the two count densities, which have a
    /// meaningful zero to divide by. Sentiment does not — see
    /// `sentimentFlatnessBand`.
    static let markerFlatnessCeiling = 0.20

    /// Flatness band for sentiment: an absolute standard deviation on
    /// NLTagger's raw -1...1 scale, not a coefficient of variation.
    ///
    /// CV over a signed scale shifted into 0...2 is ASYMMETRIC. `{0.9, 0.5,
    /// 0.7}` and `{-0.9, -0.5, -0.7}` have an identical standard deviation,
    /// but shifted CV reads 0.096 for the first (flat) and 0.544 for the
    /// second (not flat) — a positive theme earned "it sounds the same each
    /// time" while an identically-varying negative one was refused it, which
    /// is the one direction this app must never get wrong. Sentiment's zero
    /// is a midpoint, not an absence, so there is no denominator to divide
    /// by; an absolute band is the honest instrument.
    ///
    /// 0.20 is exactly the spread the CV ceiling already granted at the
    /// scale's midpoint (mean 0 → shifted mean 1.0 → allowed sd 0.20), so
    /// this corrects the asymmetry without tightening or loosening the bar.
    static let sentimentFlatnessBand = 0.20

    /// Minimum modal tokens ONE walk's theme-carrying speech must hold
    /// before `frameConstancy` will name a dominant family for that walk.
    /// Without a floor a single "can" makes a walk possibility-dominant, and
    /// `possibility` leads `MarkerLexicons.ModalFamily.allCases`, so it won
    /// every tie — the same shape as `weatherWeave`'s plurality tautology
    /// (fixed in PR #71) and `questionDensity`'s unfloored count (cut at the
    /// 2026-08-25 ship gate).
    ///
    /// Deliberately BELOW `ThreadsDossierFormatter.modalRemarkableMinCount`
    /// (10): that gate weighs a walk's ENTIRE speech and stands alone as a
    /// single-walk claim, while this one weighs a strict subset — only the
    /// recordings that carried the theme — and the sentence it guards
    /// additionally requires the same family across at least
    /// `minimumInvariantWalks` walks. The evidence behind one rendered line
    /// is therefore at least 3 × 5 = 15 modal tokens, above the sibling's
    /// single-walk bar, whereas a floor of 10 on a theme-scoped subset would
    /// make the signal effectively unfirable.
    static let frameConstancyMinModalsPerWalk = 5
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
            // Every theme the line names is reserved, not just the anchor —
            // `fusedThemes` prints two, and a lower-ranked signal making its
            // own measured claim about the second reads as covering both.
            let claimed = line.claimedLemmas
            guard !claimed.contains(where: used.contains) else { continue }
            used.formUnion(claimed)
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

    /// Recordings whose stored context was analyzed as English.
    ///
    /// `unmovedReturn` and `frameConstancy` are English-gated by accident:
    /// both read `MarkerPack`, and `MarkerAnalyzer.compute` returns nil for
    /// anything but `"en"`. `fusedThemes` and `placeFrameLock` read only
    /// themes and coordinates, so nothing gated them at all — and
    /// `TranscriptNLP.contentLemmaMentions` falls back to the LOWERCASED
    /// SURFACE FORM wherever NLTagger has no lemma model for the language.
    /// This app's walkers cross the Camino in French, German, Italian,
    /// Portuguese and Spanish, where two inflections of one word become two
    /// themes: "'marche' and 'marches' have appeared in the same 4 walks,
    /// never apart" is a tautology about a single word dressed as a
    /// discovered fusion. Gated explicitly here rather than left to accident,
    /// so the whole track speaks under one stated language contract.
    static func englishRecordings(in input: DossierSenses.Input) -> Set<UUID> {
        Set(input.historicalContexts.filter { $0.languageCode == "en" }.map(\.recordingUUID))
    }

    /// Fail-closed: an appearance whose context is missing or non-English
    /// disqualifies the whole thread. Every thread is built from the same
    /// contexts `englishRecordings` scans (`ThreadStore.build`), so a missing
    /// entry means the record disagrees with itself and silence is correct.
    static func isEnglishThroughout(_ thread: WalkThread, english: Set<UUID>) -> Bool {
        thread.appearances.allSatisfy { english.contains($0.recordingUUID) }
    }

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
    /// BOTH themes are reserved, not just the anchor (`secondaryLemma`): the
    /// line prints two display terms, so a lower-ranked signal that went on
    /// to make its own measured claim about the superset would read as a
    /// second, independent finding about a theme this line already spoke for.
    ///
    /// Deterministic: threads arrive lemma-sorted from `ThreadStore.build`,
    /// and only a STRICTLY larger shared-walk count replaces the best pair.
    static func fusedThemes(
        input: DossierSenses.Input, suppressed: Set<String>
    ) -> DossierSenses.SenseLine? {
        let english = englishRecordings(in: input)
        let candidates = input.threads
            .filter { !suppressed.contains($0.lemma) && isEnglishThroughout($0, english: english) }
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
                lemma: best.subset.lemma,
                secondaryLemma: best.superset.lemma
            )
        }

        return DossierSenses.SenseLine(
            text: "'\(best.subset.displayTerm)' has appeared in \(best.shared) walks, always alongside "
                + "'\(best.superset.displayTerm)' — which walked \(best.outer) in all.",
            lemma: best.subset.lemma,
            secondaryLemma: best.superset.lemma
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
            let sentiment = packsByWalk.map { average($0.map { $0.sentiment ?? 0 }) }

            guard isFlat(absolutist), isFlat(firstPerson), isSentimentFlat(sentiment) else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has returned across \(packsByWalk.count) walks; "
                    + "it sounds the same each time.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// Standard deviation at or under `sentimentFlatnessBand`, measured on
    /// the raw -1...1 scale. Sentiment is the one marker here whose zero is
    /// a midpoint rather than an absence, so it has no denominator a ratio
    /// measure could divide by — and dividing by a shifted one made the
    /// verdict depend on the sign of the mood rather than on its steadiness.
    /// See `sentimentFlatnessBand`.
    static func isSentimentFlat(_ values: [Double]) -> Bool {
        guard values.count >= 2 else { return false }
        let mean = average(values)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() <= sentimentFlatnessBand
    }

    /// Coefficient of variation at or under the flatness ceiling — for the
    /// two count densities only, which have a meaningful zero. A zero or
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
    /// THE SENTENCE IS SCOPED TO THE SPEECH THAT CARRIED THE THEME, not to
    /// the walk. The evidence is only the recordings the theme appears in —
    /// `thread.appearances` — and multi-recording walks are ordinary, so a
    /// walk can be, say, counterfactual-dominant overall while the two
    /// recordings that mentioned 'money' are obligation-dominant. The old
    /// wording ("Every walk where 'X' appears is Y-dominant") made a claim
    /// about the WALK on evidence drawn from a subset of it. The rendered
    /// line now says "the speech carrying it", which is exactly the set
    /// summed below — the same re-scoping `placeFrameLock` took to "Every
    /// time '_' was spoken with its location known", and the same precedent
    /// `markerColoring` sets with its ±15-token window.
    ///
    /// `ThreadsDossierFormatter.modalLeanSummary` is NOT the same
    /// computation, and this is not a mirror of it: that one sums ALL of a
    /// walk's recordings to name the walk's own lean. Only the per-walk
    /// summing MOVE is shared — when more than one theme-carrying recording
    /// lands on one walk, their modal counts are added into a single total
    /// before a dominant family is picked, rather than letting one
    /// recording's dominance silently stand for the walk.
    ///
    /// Grouped and gated by distinct WALK, not by qualifying recording,
    /// mirroring `fusedThemes` and `unmovedReturn`: a theme argued in three
    /// bursts on one walk is one data point about one frame, not three.
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
    /// dominate with 40% of the modals as long as nothing beats it — but it
    /// must beat something: see `dominantModalFamily` for the count floor
    /// and the tie rule that keep the mode from being a coin toss.
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
                text: "On every walk where '\(thread.displayTerm)' appears, the speech carrying it "
                    + "was \(first.rawValue)-dominant.",
                lemma: thread.lemma
            )
        }
        return nil
    }

    /// The dominant `ModalFamily` for one walk's summed theme-carrying modal
    /// counts, or nil if there is no honest answer.
    ///
    /// Three ways to answer nil, and the last two are the point:
    /// 1. No word present maps to a known family.
    /// 2. Fewer than `frameConstancyMinModalsPerWalk` mapped tokens in all —
    ///    a single "can" is not a frame.
    /// 3. The top two families TIE. `modalLeanSummary` resolves a tie by
    ///    declaration order over `ModalFamily.allCases`, which is safe there
    ///    only because it also sits behind `modalRemarkableMinCount` (10)
    ///    and a 2× baseline elevation. This function had neither, so
    ///    `possibility` — first in `allCases` — won every tie silently. A
    ///    tie means the walk had no dominant frame, so it holds the whole
    ///    signal silent rather than electing one.
    private static func dominantModalFamily(in modals: [String: Int]) -> MarkerLexicons.ModalFamily? {
        var totals: [MarkerLexicons.ModalFamily: Int] = [:]
        for (word, count) in modals {
            guard let family = MarkerLexicons.modalFamily(of: word) else { continue }
            totals[family, default: 0] += count
        }
        guard totals.values.reduce(0, +) >= frameConstancyMinModalsPerWalk else { return nil }

        var best: (family: MarkerLexicons.ModalFamily, count: Int)?
        var runnerUp = 0
        for family in MarkerLexicons.ModalFamily.allCases {
            let count = totals[family] ?? 0
            guard count > 0 else { continue }
            if let current = best, count <= current.count {
                runnerUp = max(runnerUp, count)
            } else {
                if let current = best { runnerUp = max(runnerUp, current.count) }
                best = (family, count)
            }
        }
        guard let best, best.count > runnerUp else { return nil }
        return best.family
    }
}
