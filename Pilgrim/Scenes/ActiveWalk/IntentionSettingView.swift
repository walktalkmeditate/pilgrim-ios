import SwiftUI

struct IntentionSettingView: View {

    @ObservedObject var historyStore: IntentionHistoryStore
    let onSet: (String) -> Void
    let onDismiss: () -> Void

    @State private var text = ""
    @State private var cachedSuggestions: [String] = []
    @StateObject private var recorder = IntentionVoiceRecorder()
    @FocusState private var isTextFieldFocused: Bool

    private let maxCharacters = 140

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)

            if recorder.isRecording {
                voiceRecordingView
                    .padding(.top, Constants.UI.Padding.big)
            } else if recorder.isTranscribing {
                transcribingView
                    .padding(.top, Constants.UI.Padding.big)
            } else {
                textInputSection
                    .padding(.top, Constants.UI.Padding.big)

                if text.isEmpty {
                    if UserPreferences.celestialAwarenessEnabled.value {
                        celestialSuggestions
                            .padding(.top, Constants.UI.Padding.normal)
                    }

                    if !historyStore.intentions.isEmpty {
                        historySection
                            .padding(.top, Constants.UI.Padding.normal)
                    }
                }
            }

            Spacer()

            bottomButtons
                .padding(.bottom, Constants.UI.Padding.big)
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .onAppear {
            if UserPreferences.celestialAwarenessEnabled.value {
                cachedSuggestions = celestialIntentionSuggestions()
            }
        }
        .onChange(of: recorder.transcribedText) { _, transcribed in
            if let transcribed {
                text = String(transcribed.prefix(maxCharacters))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Text("Set Your Intention")
            .font(Constants.Typography.heading)
            .foregroundColor(Color.ink.opacity(0.8))
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            TextField("What purpose guides this walk?", text: $text, axis: .vertical)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .lineLimit(3)
                .focused($isTextFieldFocused)
                .onChange(of: text) { _, newValue in
                    if newValue.count > maxCharacters {
                        text = String(newValue.prefix(maxCharacters))
                    }
                }
                .padding(Constants.UI.Padding.normal)
                .background(
                    RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                        .fill(Color.parchmentSecondary.opacity(0.5))
                )

            HStack {
                Button {
                    isTextFieldFocused = false
                    recorder.startRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic")
                            .font(.caption)
                        Text("Voice")
                            .font(Constants.Typography.caption)
                    }
                    .foregroundColor(.fog)
                }

                Spacer()

                Text("\(text.count)/\(maxCharacters)")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.5))
            }
        }
    }

    // MARK: - Celestial Suggestions

    private var celestialSuggestions: some View {
        Group {
            if !cachedSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                    Text("Suggested")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))

                    FlowLayout(spacing: Constants.UI.Padding.small) {
                        ForEach(cachedSuggestions, id: \.self) { suggestion in
                            Button {
                                text = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(Constants.Typography.caption)
                                    .foregroundColor(.ink.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: 250)
                                    .background(
                                        Capsule()
                                            .fill(Color.dawn.opacity(0.15))
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private func celestialIntentionSuggestions() -> [String] {
        let system = ZodiacSystem(rawValue: UserPreferences.zodiacSystem.value) ?? .tropical
        let snapshot = CelestialCalculator.snapshot(for: Date(), system: system)
        var suggestions: [String] = []

        if let marker = snapshot.seasonalMarker {
            switch marker {
            case .springEquinox: suggestions.append("Cross a threshold")
            case .summerSolstice: suggestions.append("Walk in fullness")
            case .autumnEquinox: suggestions.append("Find balance")
            case .winterSolstice: suggestions.append("Honor the stillness")
            case .imbolc: suggestions.append("Notice what's stirring")
            case .beltane: suggestions.append("Celebrate what's alive")
            case .lughnasadh: suggestions.append("Gather what you've grown")
            case .samhain: suggestions.append("Remember what matters")
            }
        }

        let retrogrades = snapshot.retrogradePlanets
        if retrogrades.contains(.mercury) {
            suggestions.append("Revisit something left unsaid")
        } else if retrogrades.contains(.venus) {
            suggestions.append("Reconsider what you value")
        } else if retrogrades.contains(.mars) {
            suggestions.append("Slow down, redirect energy")
        }

        let lunar = LunarPhase.current()
        if lunar.illumination > 0.97 {
            suggestions.append("Release what no longer serves")
        } else if lunar.illumination < 0.03 {
            suggestions.append("Plant a seed of beginning")
        }

        if let dominant = snapshot.elementBalance.dominant {
            switch dominant {
            case .water: suggestions.append("Follow what flows")
            case .fire: suggestions.append("Walk with purpose")
            case .earth: suggestions.append("Feel the ground beneath you")
            case .air: suggestions.append("Let thoughts move freely")
            }
        }

        return Array(suggestions.prefix(3))
    }

    // MARK: - History Suggestions

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Recent")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.5))

            FlowLayout(spacing: Constants.UI.Padding.small) {
                ForEach(historyStore.intentions, id: \.self) { intention in
                    Button {
                        text = intention
                    } label: {
                        Text(intention)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.ink.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: 250)
                            .background(
                                Capsule()
                                    .fill(Color.parchmentSecondary.opacity(0.4))
                            )
                    }
                }
            }
        }
    }

    // MARK: - Voice Recording

    private var voiceRecordingView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            waveformBar

            Text(formatCountdown(recorder.timeRemaining))
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

    private var waveformBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { i in
                let normalized = recorder.audioLevel
                let barHeight = max(4, CGFloat(normalized) * 40 * randomFactor(for: i))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.moss.opacity(0.5))
                    .frame(width: 4, height: barHeight)
                    .animation(.easeOut(duration: 0.1), value: normalized)
            }
        }
        .frame(height: 44)
    }

    private func randomFactor(for index: Int) -> CGFloat {
        let seed = Double(index) * 0.7
        return CGFloat(0.5 + abs(sin(seed)) * 0.5)
    }

    // MARK: - Transcribing

    private var transcribingView: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            SwiftUI.ProgressView()
                .tint(.fog)
            Text("Transcribing...")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack {
            Button("Cancel") {
                recorder.cancel()
                onDismiss()
            }
            .font(Constants.Typography.button)
            .foregroundColor(.fog)

            Spacer()

            Button("Set") {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                historyStore.add(trimmed)
                onSet(trimmed)
            }
            .font(Constants.Typography.button)
            .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .fog.opacity(0.3) : .stone)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return "\(total)s"
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {

    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
