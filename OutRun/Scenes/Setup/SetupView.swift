import SwiftUI

struct SetupView: View {

    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        VStack {
            Spacer()

            SetupPermissionsView(canContinue: viewModel.bindingForStep(0))

            Spacer()

            RoundedButton(viewModel.nextButtonTitle, action: viewModel.next)
                .disabled(!viewModel.isNextButtonEnabled.wrappedValue)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.vertical, Constants.UI.Padding.normal)
        .background(Color.parchment)
    }
}
