import SwiftUI

struct FeedbackView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: FeedbackCategory?
    @State private var message = ""
    @State private var includeDeviceInfo = true
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if showConfirmation {
                confirmationOverlay
            } else {
                formContent
            }
        }
        .background(Color.parchment)
        .navigationTitle("Trail Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Leave a Trail Note")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(spacing: Constants.UI.Padding.big) {
                categoryCards
                textEditor
                deviceInfoToggle
                if let errorMessage {
                    Text(errorMessage)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.rust)
                }
                sendButton
            }
            .padding(Constants.UI.Padding.big)
        }
    }

    private var categoryCards: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            ForEach(FeedbackCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: Constants.UI.Padding.normal) {
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundColor(.stone)
                            .frame(width: 28)
                        Text(category.title)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        if selectedCategory == category {
                            Image(systemName: "checkmark")
                                .foregroundColor(.moss)
                                .font(Constants.Typography.caption)
                        }
                    }
                    .padding(Constants.UI.Padding.normal)
                    .background(
                        selectedCategory == category
                            ? Color.stone.opacity(0.08)
                            : Color.parchmentSecondary
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                            .stroke(
                                selectedCategory == category ? Color.stone : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .cornerRadius(Constants.UI.CornerRadius.normal)
                }
            }
        }
    }

    private var textEditor: some View {
        TextEditor(text: $message)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120)
            .padding(Constants.UI.Padding.small)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .overlay(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What's on your mind?")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog.opacity(0.5))
                        .padding(Constants.UI.Padding.small)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
    }

    private var deviceInfoToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $includeDeviceInfo) {
                Text("Include device info")
                    .font(Constants.Typography.body)
            }
            .tint(.stone)
            if includeDeviceInfo {
                Text(deviceInfoPreview)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    private var deviceInfoPreview: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model) · v\(version)"
    }

    private var sendButton: some View {
        Button {
            submit()
        } label: {
            Group {
                if isSubmitting {
                    SwiftUI.ProgressView()
                        .tint(.parchment)
                } else {
                    Text("Send")
                        .font(Constants.Typography.button)
                }
            }
            .foregroundColor(.parchment)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(canSubmit ? Color.stone : Color.fog.opacity(0.2))
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .disabled(!canSubmit || isSubmitting)
    }

    private var canSubmit: Bool {
        selectedCategory != nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Submit

    private func submit() {
        guard let category = selectedCategory else { return }
        errorMessage = nil
        isSubmitting = true

        Task {
            do {
                try await FeedbackService.submit(
                    category: category.apiValue,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    includeDeviceInfo: includeDeviceInfo
                )
                withAnimation(.easeInOut(duration: 0.5)) {
                    showConfirmation = true
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                dismiss()
            } catch {
                errorMessage = "Couldn't send — please try again"
                isSubmitting = false
            }
        }
    }

    // MARK: - Confirmation

    private var confirmationOverlay: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.largeTitle)
                .foregroundColor(.moss)
            Text("Your note has been\nleft on the path.")
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .multilineTextAlignment(.center)
            Text("Thank you.")
                .font(Constants.Typography.body.italic())
                .foregroundColor(.fog)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.parchment)
        .transition(.opacity)
    }
}

// MARK: - FeedbackCategory

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug, feature, thought

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return "Something's broken"
        case .feature: return "I wish it could..."
        case .thought: return "A thought"
        }
    }

    var icon: String {
        switch self {
        case .bug: return "ladybug"
        case .feature: return "sparkles"
        case .thought: return "leaf"
        }
    }

    var apiValue: String {
        switch self {
        case .bug: return "bug"
        case .feature: return "feature"
        case .thought: return "feedback"
        }
    }
}
