import SwiftUI

struct StonePlacementSheet: View {

    let currentLocation: TempRouteDataSample?
    let nearbyCairn: CachedCairn?
    let onPlace: () -> Void
    let onDismiss: () -> Void

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
        let tier = cairn.tier
        return VStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: tier.rawValue >= CairnTier.medium.rawValue ? "mountain.2.fill" : "mountain.2")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.stone)

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
            Image(systemName: "mountain.2")
                .font(Constants.Typography.displayLarge)
                .foregroundColor(.stone.opacity(0.4))

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
