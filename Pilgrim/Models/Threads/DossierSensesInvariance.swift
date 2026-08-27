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
        case .unmovedReturn: return nil
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

        var best: (a: WalkThread, b: WalkThread, shared: Int, outer: Int)?
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                let (first, second) = (candidates[i], candidates[j])
                let isNested = first.walks.isSubset(of: second.walks)
                    || second.walks.isSubset(of: first.walks)
                guard isNested else { continue }
                let shared = first.walks.intersection(second.walks).count
                let outer = max(first.walks.count, second.walks.count)
                guard best == nil || shared > best!.shared else { continue }
                best = (first.thread, second.thread, shared, outer)
            }
        }

        guard let best else { return nil }
        return DossierSenses.SenseLine(
            text: "'\(best.a.displayTerm)' and '\(best.b.displayTerm)' have appeared in "
                + "\(best.shared) of \(best.outer) walks together, never apart.",
            lemma: best.a.lemma
        )
    }
}
