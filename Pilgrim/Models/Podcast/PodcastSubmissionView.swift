import SwiftUI

struct PodcastSubmissionView: View {

    let walk: WalkInterface

    @State private var consentChecked = false
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    private let service = PodcastSubmissionService.shared

    var body: some View {
        VStack(spacing: Constants.UI.Padding.big) {
            header
            if submitted {
                submittedView
            } else if service.hasConsent {
                submitButton
            } else {
                consentView
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(.stone)

            Text("Pilgrim on the Path")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)

            Text("Submit your walk for a podcast episode. Every walker is a pilgrim on the path \u{2014} all submissions are anonymous.")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Consent

    private var consentView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Button {
                consentChecked.toggle()
            } label: {
                HStack(alignment: .top, spacing: Constants.UI.Padding.small) {
                    Image(systemName: consentChecked ? "checkmark.square.fill" : "square")
                        .foregroundColor(consentChecked ? .stone : .fog)
                        .font(.system(size: 20))

                    Text("I consent to my voice recordings being used in an anonymous podcast episode. Recordings are unedited. I can request removal at hello@walktalkmeditate.org.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.ink)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)

            submitAction
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        submitAction
    }

    private var submitAction: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Button {
                performSubmit()
            } label: {
                HStack(spacing: Constants.UI.Padding.small) {
                    if isSubmitting {
                        SwiftUI.ProgressView()
                            .tint(.parchment)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text(isSubmitting ? "Submitting..." : "Submit Walk")
                        .font(Constants.Typography.button)
                }
                .foregroundColor(.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Constants.UI.Padding.normal - Constants.UI.Padding.xs)
                .background(canSubmit ? Color.stone : Color.fog)
                .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .disabled(!canSubmit || isSubmitting)

            if let errorMessage {
                Text(errorMessage)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.rust)
            }
        }
    }

    private var canSubmit: Bool {
        service.hasConsent || consentChecked
    }

    // MARK: - Submitted

    private var submittedView: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.moss)

            Text("Walk submitted")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)

            Text("Your walk may appear in a future episode. Thank you for walking with us.")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Constants.UI.Padding.normal)
    }

    // MARK: - Action

    private func performSubmit() {
        if !service.hasConsent {
            guard consentChecked else { return }
            service.grantConsent()
        }

        isSubmitting = true
        errorMessage = nil

        let deviceToken = ShareService.deviceTokenForFeedback()

        Task {
            do {
                try await service.submit(walk: walk, deviceToken: deviceToken)
                await MainActor.run {
                    isSubmitting = false
                    submitted = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

}
