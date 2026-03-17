import SwiftUI

struct WaypointChip: Identifiable {
    let id = UUID()
    let label: String
    let icon: String

    static let presets: [WaypointChip] = [
        WaypointChip(label: "Peaceful", icon: "leaf"),
        WaypointChip(label: "Beautiful", icon: "eye"),
        WaypointChip(label: "Grateful", icon: "heart"),
        WaypointChip(label: "Resting", icon: "figure.seated.side"),
        WaypointChip(label: "Inspired", icon: "sparkles"),
        WaypointChip(label: "Arrived", icon: "flag.fill"),
    ]
}

struct WaypointMarkingSheet: View {

    let onMark: (String, String) -> Void
    let onDismiss: () -> Void

    @State private var customText = ""
    @FocusState private var isTextFieldFocused: Bool

    private let maxCharacters = 50
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)

            chipGrid
                .padding(.top, Constants.UI.Padding.big)

            customInput
                .padding(.top, Constants.UI.Padding.normal)

            Spacer()

            Button("Cancel") { onDismiss() }
                .font(Constants.Typography.button)
                .foregroundColor(.fog)
                .padding(.bottom, Constants.UI.Padding.big)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
    }

    // MARK: - Header

    private var header: some View {
        Text("Drop a Waypoint")
            .font(Constants.Typography.heading)
            .foregroundColor(Color.ink.opacity(0.8))
    }

    // MARK: - Chip Grid

    private var chipGrid: some View {
        LazyVGrid(columns: columns, spacing: Constants.UI.Padding.small) {
            ForEach(WaypointChip.presets) { chip in
                Button {
                    onMark(chip.label, chip.icon)
                } label: {
                    VStack(spacing: Constants.UI.Padding.xs) {
                        Image(systemName: chip.icon)
                            .font(.title3)
                            .foregroundColor(.stone)
                        Text(chip.label)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.ink.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.UI.Padding.normal)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                            .fill(Color.parchmentSecondary.opacity(0.4))
                    )
                }
            }
        }
    }

    // MARK: - Custom Input

    private var customInput: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.small) {
                TextField("Custom note", text: $customText)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                    .focused($isTextFieldFocused)
                    .onChange(of: customText) { _, newValue in
                        if newValue.count > maxCharacters {
                            customText = String(newValue.prefix(maxCharacters))
                        }
                    }

                Button {
                    let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onMark(trimmed, "mappin")
                } label: {
                    Text("Mark")
                        .font(Constants.Typography.button)
                        .foregroundColor(customTextTrimmed.isEmpty ? .fog.opacity(0.3) : .stone)
                }
                .disabled(customTextTrimmed.isEmpty)
            }
            .padding(Constants.UI.Padding.normal)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                    .fill(Color.parchmentSecondary.opacity(0.5))
            )

            HStack {
                Spacer()
                Text("\(customText.count)/\(maxCharacters)")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.5))
            }
        }
    }

    private var customTextTrimmed: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
