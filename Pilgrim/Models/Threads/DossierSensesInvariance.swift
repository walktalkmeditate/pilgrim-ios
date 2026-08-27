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
    static func invarianceLines(
        input: Input,
        evaluate: (Invariant, Input, Set<String>) -> SenseLine? = {
            DossierSenses.evaluateInvariant($0, input: $1, suppressed: $2)
        }
    ) -> [String] {
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
        case .frameConstancy: return nil
        case .placeFrameLock: return nil
        case .unarrivedIntention: return nil
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
                    + "\(best.shared) of \(best.outer) walks together, never apart.",
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
            let walks = Set(qualifying.map(\.walkUUID))
            guard walks.count >= minimumInvariantWalks else { continue }

            let packs = qualifying.map(\.markers)
            let absolutist = packs.map { Double($0.absolutistCount) / Double($0.wordCount) }
            let firstPerson = packs.map { Double($0.firstPersonCount) / Double($0.wordCount) }
            let sentiment = packs.compactMap { $0.sentiment }.map { $0 + sentimentShift }
            guard sentiment.count == packs.count else { continue }

            guard isFlat(absolutist), isFlat(firstPerson), isFlat(sentiment) else { continue }

            return DossierSenses.SenseLine(
                text: "'\(thread.displayTerm)' has returned across \(walks.count) walks; "
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
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return false }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (variance.squareRoot() / mean) <= markerFlatnessCeiling
    }
}
