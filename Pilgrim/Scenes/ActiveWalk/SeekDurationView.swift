import SwiftUI

/// The one seek setup question (R2): "How long do you have?" Four presets,
/// last choice preselected, first-seek-only safety caption (R21).
struct SeekDurationView: View {

    let showsSafetyCaption: Bool
    let onContinue: (Int) -> Void
    var onCancel: (() -> Void)?

    @State private var selectedMinutes: Int

    static let presetMinutes = [30, 60, 120, 180]

    init(
        showsSafetyCaption: Bool,
        onContinue: @escaping (Int) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.showsSafetyCaption = showsSafetyCaption
        self.onContinue = onContinue
        self.onCancel = onCancel
        _selectedMinutes = State(initialValue: Self.preselectedMinutes(
            lastUsed: UserPreferences.seekLastDurationMinutes.value
        ))
    }

    /// Snaps a stored value that no longer matches a preset (e.g. after a
    /// future preset change) to the closest one instead of leaving nothing
    /// selected.
    static func preselectedMinutes(lastUsed: Int) -> Int {
        presetMinutes.min(by: { abs($0 - lastUsed) < abs($1 - lastUsed) }) ?? 60
    }

    static func label(forMinutes minutes: Int) -> String {
        switch minutes {
        case 30: return LS.seekDuration30Min
        case 60: return LS.seekDuration1Hour
        case 120: return LS.seekDuration2Hours
        default: return LS.seekDuration3Hours
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(LS.seekDurationTitle)
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            VStack(spacing: Constants.UI.Padding.small) {
                ForEach(Self.presetMinutes, id: \.self) { minutes in
                    presetRow(minutes)
                }
            }
            .padding(.top, Constants.UI.Padding.big)

            if showsSafetyCaption {
                Text(LS.seekSafetyCaption)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
                    .padding(.top, Constants.UI.Padding.normal)
            }

            Spacer()

            bottomButtons
                .padding(.bottom, Constants.UI.Padding.big)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
    }

    private func presetRow(_ minutes: Int) -> some View {
        let isSelected = minutes == selectedMinutes
        return Button {
            selectedMinutes = minutes
            UserPreferences.seekLastDurationMinutes.value = minutes
        } label: {
            HStack {
                Text(Self.label(forMinutes: minutes))
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink.opacity(isSelected ? 1.0 : 0.7))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .accessibilityHidden(true)
                }
            }
            .padding(Constants.UI.Padding.normal)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                    .fill(Color.parchmentSecondary.opacity(isSelected ? 0.7 : 0.4))
            )
        }
    }

    private var bottomButtons: some View {
        HStack {
            if let onCancel {
                Button("Cancel") { onCancel() }
                    .font(Constants.Typography.button)
                    .foregroundColor(.fog)
            }

            Spacer()

            Button(LS.seekBegin) { onContinue(selectedMinutes) }
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        }
    }
}
