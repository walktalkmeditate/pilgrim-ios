// Pilgrim/Scenes/WalkSummary/CollectiveTrailSection.swift
import SwiftUI

/// The walk summary's last widening of the lens: this walk's distance placed
/// against the day's collective route, and a sentence naming who else has
/// walked it.
///
/// Sits directly beneath the personal milestone, and is deliberately quieter
/// than it — the same icon-and-caption shape with no background fill. Two
/// identically-chromed pills stacked would read as one repeated element rather
/// than two different ideas: your own arc, then the larger one.
struct CollectiveTrailSection: View {

    /// Already phrased, and resolved by the owning summary rather than here.
    /// Building it costs an entry lookup, an ICU calendar call and a
    /// measurement formatter — twice for a cosmic horizon — and this view
    /// re-renders with its ancestor about thirty times during the distance
    /// count-up while none of its own inputs change.
    let contributionLine: String?
    /// Whether this walk actually moved the counter, read from
    /// `CollectiveContributionLog` — a past-tense fact, not the live
    /// contribution preference.
    let wasContributed: Bool
    let revealPhase: WalkSummaryView.RevealPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A beat behind the personal milestone's 0.3s rather than in lockstep
    /// with it, so the two land as two thoughts.
    private static let revealDelay: TimeInterval = 0.55

    var body: some View {
        if let line = Self.renderedLine(wasContributed: wasContributed, contributionLine: contributionLine) {
            trail(line)
        }
    }

    /// The whole render gate as one pure function, so the decision is testable
    /// without standing up a view.
    ///
    /// Both conditions are about the past rather than the present: whether this
    /// particular walk was sent to the collective, and whether a catalog exists
    /// to place it against. The catalog is nil for the first frames of every
    /// summary and stays nil if the artifact failed to load, so nothing may
    /// assume an entry on first frame.
    ///
    /// The collective's *total* is deliberately absent. The Settings line needs
    /// it and suppresses itself without it; this line does not, which is what
    /// lets a walk that ended on day twelve of a Camino with no signal still
    /// say something true.
    static func renderedLine(wasContributed: Bool, contributionLine: String?) -> String? {
        wasContributed ? contributionLine : nil
    }

    private func trail(_ line: String) -> some View {
        HStack(alignment: .top, spacing: Constants.UI.Padding.small) {
            Image(systemName: "signpost.right")
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
            Text(line)
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
                // A walk distance plus a full company sentence runs to about
                // 110 characters — several times the milestone's budget, whose
                // limits were tuned for a much shorter string.
                .minimumScaleFactor(0.5)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .opacity(revealPhase == .revealed ? 1 : 0)
        .animation(reduceMotion ? nil : .easeIn(duration: 0.8).delay(Self.revealDelay), value: revealPhase)
    }
}
