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
    var onRelease: ((ThreadsCardTheme) -> Void)?

    @State private var showInsightWords = false
    @State private var themeToRelease: ThreadsCardTheme?
    @State private var captionDismissed = UserPreferences.threadsReleaseCaptionShown.value

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
            if onRelease != nil, !captionDismissed {
                captionRow
            }
        }
        .padding(Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
        .alert(
            themeToRelease.map { ReleasedThreadsCopy.releaseTitle($0.displayTerm) } ?? "",
            isPresented: Binding(
                get: { themeToRelease != nil },
                set: { if !$0 { themeToRelease = nil } }
            ),
            presenting: themeToRelease
        ) { theme in
            Button(ReleasedThreadsCopy.releaseConfirm) {
                onRelease?(theme)
                themeToRelease = nil
            }
            Button(ReleasedThreadsCopy.releaseCancel, role: .cancel) {
                themeToRelease = nil
            }
        } message: { _ in
            Text(ReleasedThreadsCopy.releaseMessage)
        }
    }

    private var captionRow: some View {
        HStack(spacing: Constants.UI.Padding.xs) {
            Text(ReleasedThreadsCopy.caption)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.7))
            Button {
                UserPreferences.threadsReleaseCaptionShown.value = true
                captionDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.fog)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Dismiss hint")
        }
    }

    private func chip(_ theme: ThreadsCardTheme) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            onThemeTap?(theme)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard onRelease != nil else { return }
            themeToRelease = theme
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            theme.statusNote.map { "\(theme.displayTerm), \($0)" } ?? theme.displayTerm
        )
        .accessibilityHint(onThemeTap == nil ? "" : "Double tap to view history")
        .accessibilityAction(named: ReleasedThreadsCopy.voiceOverActionName) {
            guard onRelease != nil else { return }
            themeToRelease = theme
        }
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
