import SwiftUI

struct StonePlacementSheet: View {

    let currentLocation: TempRouteDataSample?
    let nearbyCairn: CachedCairn?
    let onPlace: () -> Void
    let onDismiss: () -> Void

    /// The tier this cairn becomes with the walker's stone added — the
    /// sheet shows what their stone makes, not what already stands (AE1-AE3).
    private var becomingTier: CairnTier {
        CairnTier.from(stoneCount: (nearbyCairn?.stoneCount ?? 0) + 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Place a Stone")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            VStack(spacing: Constants.UI.Padding.normal) {
                if let cairn = nearbyCairn {
                    existingCairnSection(cairn)
                } else {
                    newCairnSection
                }

                privacyNotice

                Button(action: onPlace) {
                    Text("Place Stone")
                        .font(Constants.Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.stone)
                        .foregroundColor(.parchment)
                        .cornerRadius(Constants.UI.CornerRadius.normal)
                }
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.big)

            Spacer()
        }
    }

    private func existingCairnSection(_ cairn: CachedCairn) -> some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Image(becomingTier.glyphAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityLabel("Becomes a \(becomingTier) cairn")

            Text("\(cairn.stoneCount)")
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.ink)
            + Text(" ")
            + Text(cairn.stoneCount == 1 ? "stone" : "stones")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)

            Text("Add your stone to this cairn")
                .font(Constants.Typography.body)
                .foregroundColor(.ink.opacity(0.7))
        }
    }

    private var newCairnSection: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            // View-level opacity, not a tint: the baked-color art ignores
            // foregroundColor, and "not yet placed" must still read as ghost.
            Image(becomingTier.glyphAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .opacity(0.4)
                .accessibilityLabel("Begins a faint cairn")

            Text("Start a new cairn here")
                .font(Constants.Typography.body)
                .foregroundColor(.ink.opacity(0.7))

            Text("Other pilgrims who pass this way can add their stones")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
        }
    }

    private var privacyNotice: some View {
        Text("Your location is shared anonymously. Cairns are permanent landmarks.")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
