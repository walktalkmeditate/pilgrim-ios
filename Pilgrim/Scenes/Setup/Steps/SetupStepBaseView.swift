import SwiftUI

struct SetupStepBaseView<Content: View>: View {

    let headline: String
    let description: String
    let content: () -> Content

    var body: some View {
        VStack(alignment: .center, spacing: Constants.UI.Padding.small) {
            Text(headline)
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(description)
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
            content()
        }
    }

    internal init(
        headline: String,
        description: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.headline = headline
        self.description = description
        self.content = content
    }
}
