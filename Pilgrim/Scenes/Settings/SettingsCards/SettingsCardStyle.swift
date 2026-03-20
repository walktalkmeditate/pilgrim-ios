import SwiftUI

struct SettingsCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
    }
}

extension View {
    func settingsCard() -> some View {
        modifier(SettingsCardStyle())
    }
}

// MARK: - Shared Setting Row Builders

func cardHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(Constants.Typography.heading)
            .foregroundColor(.ink)
        Text(subtitle)
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
    }
    .padding(.bottom, Constants.UI.Padding.small)
}

func settingToggle(
    label: String,
    description: String,
    isOn: Binding<Bool>,
    onChange: @escaping (Bool) -> Void
) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            Text(description)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }
    .tint(.stone)
    .onChange(of: isOn.wrappedValue) { _, newValue in onChange(newValue) }
}

func settingPicker<T: Hashable>(
    label: String,
    selection: Binding<T>,
    options: [(String, T)],
    onChange: @escaping (T) -> Void
) -> some View {
    HStack {
        Text(label)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
        Spacer()
        Picker("", selection: selection) {
            ForEach(options, id: \.1) { option in
                Text(option.0).tag(option.1)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .onChange(of: selection.wrappedValue) { _, newValue in onChange(newValue) }
    }
}

func settingNavRow(label: String, detail: String? = nil) -> some View {
    HStack {
        Text(label)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
        Spacer()
        if let detail {
            Text(detail)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
        Image(systemName: "chevron.right")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
    }
}
