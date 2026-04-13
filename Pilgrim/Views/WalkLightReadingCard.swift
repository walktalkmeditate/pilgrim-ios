import SwiftUI

/// Inline card that renders a single `LightReading` above the share
/// section of `WalkSummaryView`. Appears after the first Share tap
/// for the walk (see `WalkSharingTracker`), fades in with a gentle
/// scale bump, and stays in place so the user can scroll back to it.
///
/// The card is intentionally sparse: an SF Symbol header, the reading
/// sentence in body serif, and a small italic caption. No decoration,
/// no animation after the reveal. Long-press copies the sentence to
/// the pasteboard with a soft haptic.
struct WalkLightReadingCard: View {

    let reading: LightReading

    var body: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: reading.symbolName)
                .font(.title2)
                .foregroundColor(.stone)
                .accessibilityHidden(true)

            Text(reading.sentence)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, Constants.UI.Padding.normal)

            Text("— a light reading")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.6))
                .italic()
        }
        .padding(.vertical, Constants.UI.Padding.big)
        .padding(.horizontal, Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .background(Color.parchment)
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A light reading for this walk: \(reading.sentence)")
        .onLongPressGesture(minimumDuration: 1.0) {
            UIPasteboard.general.string = reading.sentence
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
}

#if DEBUG
struct WalkLightReadingCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            WalkLightReadingCard(
                reading: LightReading(
                    sentence: "Your walk began 14 minutes before sunrise. The sun rose at 6:23.",
                    tier: .sunriseSunset,
                    symbolName: "sunrise"
                )
            )
            WalkLightReadingCard(
                reading: LightReading(
                    sentence: "This walk happened during a total lunar eclipse. The moon turned red.",
                    tier: .lunarEclipse,
                    symbolName: "moon.circle.fill"
                )
            )
            WalkLightReadingCard(
                reading: LightReading(
                    sentence: "You walked under a waxing gibbous moon, 78% illuminated.",
                    tier: .moonPhase,
                    symbolName: "moon.fill"
                )
            )
        }
        .padding()
        .background(Color.parchmentSecondary)
    }
}
#endif
