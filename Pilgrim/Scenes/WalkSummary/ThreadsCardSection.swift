import SwiftUI

/// Loads the card model off the summary's hot path: CoreStore reads on the
/// main actor, store I/O and thread aggregation detached, plain values
/// across the boundary (the ThreadsDossierBuilder discipline).
enum ThreadsCardLoader {

    @MainActor
    static func load(
        walk: WalkInterface,
        transcriptions: [UUID: String],
        store: TranscriptContextStore = .shared,
        releasedStore: ReleasedThreadsStore = .shared
    ) async -> ThreadsCardModel? {
        guard UserPreferences.threadsAfterWalks.value,
              let walkUUID = walk.uuid,
              !transcriptions.isEmpty else { return nil }

        let recordings = walk.voiceRecordings.compactMap { recording -> (uuid: UUID, transcript: String, wordsPerMinute: Double?)? in
            guard let uuid = recording.uuid, let text = transcriptions[uuid] else { return nil }
            return (uuid, text, recording.wordsPerMinute)
        }
        guard !recordings.isEmpty else { return nil }

        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let released = releasedStore.releasedLemmas
        let backfillComplete = ThreadsBackfill.isComplete

        return await Task.detached(priority: .userInitiated) {
            let contexts = store.loadAll()
            let contextsByRecording = Dictionary(
                uniqueKeysWithValues: contexts.map { ($0.recordingUUID, $0) }
            )
            let threads = ThreadStore.build(contexts: contexts, walks: walkIndex, released: released)
            return ThreadsCardModelBuilder.model(
                walkUUID: walkUUID,
                threads: threads,
                recordings: recordings,
                contextsByRecording: contextsByRecording,
                backfillComplete: backfillComplete
            )
        }.value
    }
}

/// "What walked with you" — the quiet card naming the themes of this walk.
/// Rendered only when a model exists: at least one transcribed recording,
/// at least one surviving theme, toggle on.
struct ThreadsCardSection: View {

    let model: ThreadsCardModel
    var onThemeTap: ((ThreadsCardTheme) -> Void)?

    @State private var showInsightWords = false

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text("What walked with you")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            FlowLayout(spacing: Constants.UI.Padding.small) {
                ForEach(model.themes) { theme in
                    chip(theme)
                }
            }
            if let texture = model.textureLine {
                textureLine(texture)
            }
        }
        .padding(Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private func chip(_ theme: ThreadsCardTheme) -> some View {
        Button {
            onThemeTap?(theme)
        } label: {
            VStack(spacing: 2) {
                Text(theme.displayTerm)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                if let note = theme.statusNote {
                    Text(note)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.moss.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(onThemeTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            theme.statusNote.map { "\(theme.displayTerm), \($0)" } ?? theme.displayTerm
        )
        .accessibilityHint(onThemeTap == nil ? "" : "Double tap to view history")
    }

    private func textureLine(_ texture: String) -> some View {
        Button {
            guard model.hasInsight else { return }
            showInsightWords.toggle()
        } label: {
            VStack(spacing: Constants.UI.Padding.xs) {
                Text(texture)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
                if showInsightWords, model.hasInsight {
                    Text(model.insightWords.map { "'\($0)'" }.joined(separator: ", "))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.moss)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            model.hasInsight ? "Double tap to see the words of insight" : ""
        )
    }
}
