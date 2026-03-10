import SwiftUI

struct RoundedButton: View {

    @Binding private var text: String
    private let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .foregroundColor(Color.parchment)
                .font(Constants.Typography.button)
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.vertical, Constants.UI.Padding.small)
                .background(Color.stone)
                .cornerRadius(Constants.UI.CornerRadius.normal)
        }
    }

    init(_ text: Binding<String>, action: @escaping () -> Void) {
        self._text = text
        self.action = action
    }

    init(_ text: String, action: @escaping () -> Void) {
        self._text = .constant(text)
        self.action = action
    }
}
