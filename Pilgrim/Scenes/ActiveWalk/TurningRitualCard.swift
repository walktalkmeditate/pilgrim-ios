import SwiftUI

/// Contemplative card shown when the user taps the turning kanji watermark
/// on the active walk. Pure ritual — no stats, no controls, just the kanji,
/// the seasonal name, and an evocative phrase. Presented as a medium sheet
/// from `ActiveWalkView`; the system drag indicator + swipe-down dismiss
/// the card.
///
/// **Dynamic Type:** the kanji uses `@ScaledMetric` so it grows with the
/// user's text-size setting. Body text uses standard typography styles
/// that scale automatically. Wrapping ScrollView lets AX5+ sizes flow
/// rather than clip inside the medium detent.
struct TurningRitualCard: View {

    let turning: SeasonalMarker

    /// Base 64pt scaled to the user's Dynamic Type setting. At AX5 it
    /// grows proportionally; ScrollView catches any overflow inside the
    /// sheet detent.
    @ScaledMetric(relativeTo: .largeTitle) private var kanjiSize: CGFloat = 64

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Constants.UI.Padding.normal) {
                Spacer(minLength: Constants.UI.Padding.big)

                if let kanji = turning.kanji {
                    Text(kanji)
                        .font(.system(size: kanjiSize, weight: .ultraLight))
                        .foregroundColor(turning.color ?? .ink)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }

                Text(turning.name)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)

                if let phrase = turning.evocativePhrase {
                    Text(phrase)
                        .font(Constants.Typography.body.italic())
                        .foregroundColor(.fog)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Constants.UI.Padding.big)
                }

                Spacer(minLength: Constants.UI.Padding.big)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(turning.name). \(turning.evocativePhrase ?? "")")
    }
}
