import SwiftUI

struct WelcomeView: View {

    @ObservedObject var viewModel: WelcomeViewModel

    var body: some View {
        VStack {
            PilgrimLogoView(size: 120)
                .padding(.top, Constants.UI.Padding.big)
            Text(viewModel.currentQuote)
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.stone)
                .multilineTextAlignment(.center)
            Spacer()
            ActionButton("Begin Setup", action: viewModel.beginAction)
        }
        .padding([.horizontal, .top], Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.normal)
        .background(Color.parchment)
    }
}
