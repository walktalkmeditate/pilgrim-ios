import SwiftUI

struct WalkShareView: View {

    @StateObject private var viewModel: WalkShareViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedToast = false
    @State private var toastGeneration = 0

    init(walk: WalkInterface) {
        _viewModel = StateObject(wrappedValue: WalkShareViewModel(walk: walk))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.big) {
                    mapPreview
                    statToggles
                    journalSection
                    expiryPicker
                    shareButton
                }
                .padding(Constants.UI.Padding.normal)
            }
            .background(Color.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Share Walk")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
        }
    }

    // MARK: - Map Preview

    private var mapPreview: some View {
        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
            .fill(Color.parchmentSecondary)
            .frame(height: 200)
            .overlay(
                Text("Route Preview")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            )
    }

    // MARK: - Stat Toggles

    private var statToggles: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            sectionLabel("Share these details")

            StatToggleRow(title: "Distance", isOn: $viewModel.toggleDistance)
            StatToggleRow(title: "Duration", isOn: $viewModel.toggleDuration)
            StatToggleRow(title: "Elevation", isOn: $viewModel.toggleElevation)
            StatToggleRow(title: "Walk / Meditation / Talk", isOn: $viewModel.toggleActivityBreakdown)
            StatToggleRow(title: "Steps", isOn: $viewModel.toggleSteps)
        }
    }

    // MARK: - Journal

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            sectionLabel("Reflection")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.journal)
                    .font(Constants.Typography.body)
                    .frame(minHeight: 60)
                    .padding(Constants.UI.Padding.small)
                    .scrollContentBackground(.hidden)
                    .background(Color.parchmentSecondary)
                    .cornerRadius(Constants.UI.CornerRadius.small)
                    .onChange(of: viewModel.journal) { _, newValue in
                        if newValue.count > 140 {
                            viewModel.journal = String(newValue.prefix(140))
                        }
                    }

                if viewModel.journal.isEmpty {
                    Text("A few words about this walk...")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog)
                        .padding(.horizontal, Constants.UI.Padding.normal)
                        .padding(.vertical, Constants.UI.Padding.normal)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Text("\(viewModel.journal.count) / 140")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Expiry Picker

    private var expiryPicker: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            sectionLabel("This walk lives for")

            HStack(spacing: Constants.UI.Padding.small) {
                ForEach(WalkShareViewModel.ExpiryOption.allCases, id: \.rawValue) { option in
                    expiryButton(option)
                }
            }

            HStack {
                Spacer()
                Text("Expires \(expiryDateFormatted)")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Spacer()
            }
        }
    }

    private func expiryButton(_ option: WalkShareViewModel.ExpiryOption) -> some View {
        let isSelected = viewModel.selectedExpiry == option
        return Button {
            viewModel.selectedExpiry = option
        } label: {
            Text(option.label)
                .font(Constants.Typography.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.stone : Color.parchmentSecondary)
                .foregroundColor(isSelected ? .parchment : .fog)
                .cornerRadius(Constants.UI.CornerRadius.small)
        }
    }

    private var expiryDateFormatted: String {
        Self.expiryFormatter.string(from: viewModel.expiryDate)
    }

    private static let expiryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        switch viewModel.shareState {
        case .idle:
            primaryButton("Share Walk") {
                Task { await viewModel.share() }
            }

        case .uploading:
            HStack(spacing: Constants.UI.Padding.small) {
                SwiftUI.ProgressView()
                    .tint(.parchment)
                Text("Sharing...")
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.stone.opacity(0.6))
            .cornerRadius(Constants.UI.CornerRadius.normal)

        case .success(let url):
            VStack(spacing: Constants.UI.Padding.normal) {
                VStack(spacing: Constants.UI.Padding.small) {
                    Text("Walk shared")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)

                    Text(url)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: Constants.UI.Padding.small) {
                    Button {
                        UIPasteboard.general.string = url
                        toastGeneration += 1
                        let gen = toastGeneration
                        showCopiedToast = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            if toastGeneration == gen { showCopiedToast = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                            Text(showCopiedToast ? "Copied" : "Copy")
                                .font(Constants.Typography.button)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.parchmentSecondary)
                        .foregroundColor(.stone)
                        .cornerRadius(Constants.UI.CornerRadius.small)
                    }

                    if let shareURL = URL(string: url) {
                        ShareLink(item: shareURL) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                                    .font(Constants.Typography.button)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.stone)
                            .foregroundColor(.parchment)
                            .cornerRadius(Constants.UI.CornerRadius.small)
                        }
                    }
                }
            }
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)

        case .error(let message):
            VStack(spacing: Constants.UI.Padding.small) {
                Text(message)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.rust)
                    .multilineTextAlignment(.center)

                primaryButton("Try Again") {
                    Task { await viewModel.share() }
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Constants.Typography.button)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.stone)
                .foregroundColor(.parchment)
                .cornerRadius(Constants.UI.CornerRadius.normal)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Constants.Typography.micro)
            .foregroundColor(.fog)
            .tracking(1.5)
    }
}

// MARK: - Stat Toggle Row

private struct StatToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.moss)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, 10)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.small)
    }
}
