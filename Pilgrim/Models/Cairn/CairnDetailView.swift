import SwiftUI

struct CairnDetailView: View {

    let cairn: CachedCairn
    let canPlaceStone: Bool
    let onPlaceStone: (() -> Void)?

    @State private var visualImage: UIImage?

    var body: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            if let image = visualImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
            }

            VStack(spacing: 4) {
                Text("\(cairn.stoneCount)")
                    .font(Constants.Typography.displayLarge)
                    .foregroundColor(.ink)

                Text(cairn.stoneCount == 1 ? "stone" : "stones")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)

                Text(tierLabel)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.stone)
                    .padding(.top, 2)
            }

            if canPlaceStone, let onPlaceStone {
                Button(action: onPlaceStone) {
                    Text("Place a Stone")
                        .font(Constants.Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.stone)
                        .foregroundColor(.parchment)
                        .cornerRadius(Constants.UI.CornerRadius.normal)
                }
                .padding(.horizontal, Constants.UI.Padding.big)
            }
        }
        .padding(Constants.UI.Padding.big)
        .task { @MainActor in
            visualImage = CairnVisualGenerator.generate(
                latitude: cairn.latitude,
                longitude: cairn.longitude,
                stoneCount: cairn.stoneCount
            )
        }
    }

    private var tierLabel: String {
        switch cairn.tier {
        case .faint: return "A faint mark"
        case .small: return "A small cairn"
        case .medium: return "A growing cairn"
        case .large: return "A steady cairn"
        case .great: return "A great cairn"
        case .sacred: return "A sacred cairn"
        case .eternal: return "An eternal cairn"
        }
    }
}
