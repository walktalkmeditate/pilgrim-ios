import SwiftUI
import AVFoundation

struct PodcastSubmissionView: View {

    let walk: WalkInterface
    var shareURL: String?

    @State private var consentChecked = false
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @State private var reflection = ""
    @State private var showMicDenied = false
    @StateObject private var recorder = IntentionVoiceRecorder()

    private let service = PodcastSubmissionService.shared
    private let maxCharacters = 140

    var body: some View {
        VStack(spacing: Constants.UI.Padding.big) {
            header
            if submitted {
                submittedView
            } else {
                reflectionSection
                if service.hasConsent {
                    submitButton
                } else {
                    consentView
                }
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .onChange(of: recorder.transcribedText) { _, transcribed in
            if let transcribed {
                reflection = String(transcribed.prefix(maxCharacters))
            }
        }
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

    // MARK: - Reflection

    private var reflectionSection: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            if recorder.isRecording {
                voiceRecordingView
            } else if recorder.isTranscribing {
                HStack(spacing: Constants.UI.Padding.small) {
                    SwiftUI.ProgressView()
                        .tint(.fog)
                    Text("Transcribing...")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                .padding(.vertical, Constants.UI.Padding.normal)
            } else {
                TextField("A few words about this walk...", text: $reflection, axis: .vertical)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                    .lineLimit(3)
                    .onChange(of: reflection) { _, newValue in
                        if newValue.count > maxCharacters {
                            reflection = String(newValue.prefix(maxCharacters))
                        }
                    }
                    .padding(Constants.UI.Padding.normal)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                            .fill(Color.parchment.opacity(0.5))
                    )

                HStack {
                    Button {
                        startVoiceRecording()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mic")
                                .font(.caption)
                            Text(showMicDenied ? "Mic access needed" : "Voice")
                                .font(Constants.Typography.caption)
                        }
                        .foregroundColor(showMicDenied ? .rust : .fog)
                    }

                    Spacer()

                    Text("\(reflection.count)/\(maxCharacters)")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))
                }
            }
        }
    }

    private var voiceRecordingView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { i in
                    let normalized = recorder.audioLevel
                    let barHeight = max(4, CGFloat(normalized) * 40 * (0.5 + abs(CGFloat(sin(Double(i) * 0.7))) * 0.5))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.moss.opacity(0.5))
                        .frame(width: 4, height: barHeight)
                        .animation(.easeOut(duration: 0.1), value: normalized)
                }
            }
            .frame(height: 44)

            Text("\(Int(recorder.timeRemaining))s")
                .font(Constants.Typography.statValue)
                .foregroundColor(.fog)
                .monospacedDigit()

            Button {
                recorder.stopRecording()
                Task { await recorder.transcribe() }
            } label: {
                Text("Done")
                    .font(Constants.Typography.button)
                    .foregroundColor(.ink)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .stroke(Color.fog.opacity(0.3), lineWidth: 1)
                    )
            }
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

                    Text("I consent to my voice recordings being considered for an anonymous podcast episode. Submissions are curated and not all walks are selected. Recordings are unedited. I can request removal at hello@walktalkmeditate.org.")
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

    // MARK: - Voice

    private func startVoiceRecording() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            recorder.startRecording()
        case .denied:
            showMicDenied = true
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        recorder.startRecording()
                    } else {
                        showMicDenied = true
                    }
                }
            }
        @unknown default:
            break
        }
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
                let trimmedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
                try await service.submit(
                    walk: walk,
                    deviceToken: deviceToken,
                    shareURL: shareURL,
                    reflection: trimmedReflection.isEmpty ? nil : trimmedReflection
                )
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
