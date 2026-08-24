import SwiftUI

/// The moon's quiet accounting — pulled, never pushed. Content is computed
/// live at open; themes tap through to their thread views. Deterministic
/// template copy; the only digits are the spec-sanctioned "in N of M walks".
struct LunationRecapView: View {

    let lunation: Lunation

    @Environment(\.dismiss) private var dismiss
    @State private var model: LunationRecapModel?
    @State private var selectedTheme: LunationRecapTheme?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model {
                    content(model)
                        .padding(Constants.UI.Padding.normal)
                }
            }
            .canvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(model?.moonName ?? "")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
            .navigationDestination(item: $selectedTheme) { theme in
                ThreadHistoryView(displayTerm: theme.displayTerm, cohortLemmas: theme.lemmas)
            }
            // Re-keyed on the released token: a release made inside the
            // pushed thread view pops back here, the pop re-evaluates this
            // body, the id has changed, and load() reruns — the released
            // theme drops out (the quiet line appears when emptied) and a
            // re-tap can never open a dead-end empty history view.
            .task(id: ReleasedThreadsStore.shared.changeCount) { await load() }
        }
    }

    private func content(_ model: LunationRecapModel) -> some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: "moon")
                .font(.title2)
                .foregroundColor(.fog)
                .accessibilityHidden(true)
            Text(LunationRecapCopy.headline(walkCount: model.walkCount))
                .font(Constants.Typography.body)
                .foregroundColor(.ink)

            if let quiet = model.quietLine {
                Text(quiet)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
            }

            ForEach(model.themes) { theme in
                themeRow(theme, totalWalks: model.walkCount)
            }

            if let texture = model.textureLine {
                Text(texture)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func themeRow(_ theme: LunationRecapTheme, totalWalks: Int) -> some View {
        Button {
            selectedTheme = theme
        } label: {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                Text(LunationRecapCopy.themeLine(
                    term: theme.displayTerm, walkCount: theme.walkCount, totalWalks: totalWalks
                ))
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .multilineTextAlignment(.leading)
                if theme.isNewThisMoon {
                    Text(LunationRecapCopy.newThisMoon)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.moss)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to view this thread's history")
    }

    @MainActor
    private func load() async {
        // The local shadow must precede its first use — Swift resolves the
        // unqualified name to the local for the WHOLE scope, so referencing
        // it above its declaration is a compile error, not a property read.
        let lunation = self.lunation
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let paces = DataManager.voiceRecordingPaceIndex()
        let released = ReleasedThreadsStore.shared.releasedLemmas
        let backfillComplete = ThreadsBackfill.isComplete
        let moonName = LunationCalendar.moonName(for: lunation)

        model = await Task.detached(priority: .userInitiated) {
            LunationRecapModelBuilder.model(
                lunation: lunation, moonName: moonName,
                contexts: TranscriptContextStore.shared.loadAll(),
                walkIndex: walkIndex, paceByRecording: paces,
                released: released, backfillComplete: backfillComplete
            )
        }.value
    }
}
