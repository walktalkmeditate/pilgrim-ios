// Pilgrim/Scenes/WalkSummary/CollectiveTrailSection.swift
import SwiftUI

/// This walk's distance against the day's collective route, and a sentence naming
/// who else has walked it. No background fill, so it doesn't read as a second milestone.
struct CollectiveTrailSection: View {

    /// Already phrased, and resolved by the owning summary rather than here: this
    /// body is a bare `if let`, so the view is `EmptyView` on exactly the frames
    /// where it would need to resolve, and no lifecycle callback would fire.
    let contributionLine: String?
    /// A past-tense fact from `CollectiveContributionLog`, not the live preference.
    let wasContributed: Bool
    let revealPhase: WalkSummaryView.RevealPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A beat behind the personal milestone's 0.3s, so the two land as two thoughts.
    private static let revealDelay: TimeInterval = 0.55

    var body: some View {
        if let line = Self.renderedLine(wasContributed: wasContributed, contributionLine: contributionLine) {
            trail(line)
        }
    }

    /// The render gate as a pure function, so it is testable without a view. No
    /// collective total involved — unlike the Settings line, this one still holds
    /// on day twelve of a Camino with no signal.
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
                // A walk distance plus a company sentence runs to ~110 characters.
                .minimumScaleFactor(0.5)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .opacity(revealPhase == .revealed ? 1 : 0)
        .animation(reduceMotion ? nil : .easeIn(duration: 0.8).delay(Self.revealDelay), value: revealPhase)
    }
}
