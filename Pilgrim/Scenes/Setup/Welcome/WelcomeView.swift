import SwiftUI

struct WelcomeView: View {

    @ObservedObject var viewModel: WelcomeViewModel

    var body: some View {
        VStack {
            PilgrimLogoView(size: 120)
                .padding(.top, Constants.UI.Padding.big)
            Text(viewModel.titleLineOne)
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.fog)
            Text(viewModel.titleLineTwo)
                .font(Constants.Typography.displayLarge)
                .foregroundColor(.stone)
            Spacer()
            ForEach(viewModel.features, id: \.title) { viewModel in
                FeatureView(viewModel: viewModel)
            }
            Spacer()
            ActionButton(viewModel.actionButtonTitle, action: viewModel.setupButtonAction)
        }
        .padding([.horizontal, .top], Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.normal)
        .background(Color.parchment)
    }
}
