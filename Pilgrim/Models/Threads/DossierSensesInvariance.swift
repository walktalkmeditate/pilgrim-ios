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
        case .fusedThemes: return nil
        case .unmovedReturn: return nil
        case .frameConstancy: return nil
        case .placeFrameLock: return nil
        case .unarrivedIntention: return nil
        }
    }
}
