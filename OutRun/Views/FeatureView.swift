import SwiftUI

struct FeatureView: View {

    let viewModel: FeatureViewModel

    var body: some View {
        AxisGeometryReader(axis: .horizontal, alignment: .leading) { width in
            HStack(spacing: Constants.UI.Padding.normal) {
                Image(systemName: viewModel.systemImageName)
                    .font(.system(size: 48))
                    .frame(width: width / 6)
                    .foregroundColor(.stone)
                VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                    Text(viewModel.title)
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                    Text(viewModel.description)
                        .font(.subheadline)
                        .foregroundColor(.fog)
                }
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }
}
