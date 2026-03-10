import SwiftUI

struct ActionButton: View {

    @Binding private var text: String
    private let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .foregroundColor(Color.parchment)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.parchment)
            }
            .font(Constants.Typography.button)
            .padding(Constants.UI.Padding.normal)
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
