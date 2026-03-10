import SwiftUI

struct PermissionView: View {

    private let title: String
    private let subtitle: String?
    @Binding private var granted: Bool
    private let showExplanation: () -> Void
    private let showPermissionMenu: () -> Void

    var body: some View {
        CardView {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: showExplanation) {
                        Text(title)
                            .font(Constants.Typography.button)
                            .foregroundColor(.ink)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
                Spacer()
                Button(action: showPermissionMenu) {
                    ZStack {
                        Text("GRANT")
                            .opacity(granted ? 0 : 1)
                        Image(systemName: "checkmark")
                            .opacity(granted ? 1 : 0)
                    }
                    .foregroundColor(Color.parchment)
                    .font(.subheadline.bold())
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
                .background(granted ? Color.moss : Color.fog)
                .clipShape(Capsule())
                .animation(.easeOut, value: granted)
            }
        }
    }

    init(
        title: String,
        subtitle: String? = nil,
        granted: Binding<Bool>,
        showExplanation: @escaping () -> Void,
        showPermissionMenu: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self._granted = granted
        self.showExplanation = showExplanation
        self.showPermissionMenu = showPermissionMenu
    }
}
