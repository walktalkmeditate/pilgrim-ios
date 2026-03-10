import SwiftUI

struct CardView<Content: View>: View {

    private let content: () -> Content

    var body: some View {
        content()
            .frame(height: 50)
            .padding(.horizontal, Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}
