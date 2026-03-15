import SwiftUI

struct FaviconSelectorView: View {

    @Binding var selection: WalkFavicon?

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text("Mark this walk")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)

            HStack(spacing: Constants.UI.Padding.big) {
                ForEach(WalkFavicon.allCases, id: \.self) { fav in
                    faviconButton(fav)
                }
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private func faviconButton(_ fav: WalkFavicon) -> some View {
        let isSelected = selection == fav
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = isSelected ? nil : fav
            }
        } label: {
            VStack(spacing: Constants.UI.Padding.xs) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.stone : Color.fog.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: fav.icon)
                        .font(Constants.Typography.statValue)
                        .foregroundColor(isSelected ? .parchment : .fog)
                }

                Text(fav.label)
                    .font(Constants.Typography.micro)
                    .foregroundColor(isSelected ? .ink : .fog)
            }
        }
        .accessibilityLabel(fav.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
