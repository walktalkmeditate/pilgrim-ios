import SwiftUI

// MARK: - Thought Threads card glue
//
// Extracted from `WalkSummaryView.swift` like the +Map extension, to keep
// the main type body under SwiftLint's type_body_length limit. Stored
// state stays in the struct; everything else lives here.

extension WalkSummaryView {

    @ViewBuilder
    var threadsCardSlot: some View {
        if showsThreadsCard, let threadsCardModel {
            ThreadsCardSection(
                model: threadsCardModel,
                onThemeTap: { selectedCardTheme = $0 }
            )
        }
    }

    func loadThreadsCard() async {
        guard showsThreadsCard else { return }
        threadsCardModel = await ThreadsCardLoader.load(walk: walk, transcriptions: transcriptions)
    }
}
