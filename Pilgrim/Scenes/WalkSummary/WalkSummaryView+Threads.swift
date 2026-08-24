import SwiftUI

// MARK: - Thought Threads card glue
//
// Extracted from `WalkSummaryView.swift` like the +Map extension, to keep
// the main type body under SwiftLint's type_body_length limit. Stored
// state stays in the struct; everything else lives here.

extension WalkSummaryView {

    @ViewBuilder
    var threadsCardSlot: some View {
        if showsThreadsCard {
            if let recapInvitation {
                lunationInvitationRow(recapInvitation)
            }
            if let threadsCardModel {
                ThreadsCardSection(
                    model: threadsCardModel,
                    onThemeTap: { selectedCardTheme = $0 },
                    onRelease: { releaseTheme($0) }
                )
                .transition(.opacity)
            }
        }
    }

    func lunationInvitationRow(_ lunation: Lunation) -> some View {
        Button {
            LunationRecapState.shared.markActedOn(lunation)
            recapInvitation = nil
            recapSheet = lunation
        } label: {
            HStack(spacing: Constants.UI.Padding.small) {
                Image(systemName: "moon")
                    .font(.caption)
                    .foregroundColor(.fog)
                Text(LunationRecapCopy.invitation(
                    moonName: LunationCalendar.moonName(for: lunation)
                ))
                .font(Constants.Typography.caption)
                .foregroundColor(.ink)
                .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(Constants.UI.Padding.normal)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to open the moon's recap")
    }

    func loadThreadsCard() async {
        guard showsThreadsCard else { return }
        threadsCardModel = await ThreadsCardLoader.load(walk: walk, transcriptions: transcriptions)
    }

    func releaseTheme(_ theme: ThreadsCardTheme) {
        ReleasedThreadsStore.shared.release(displayTerm: theme.displayTerm, lemmas: theme.lemmas)
        withAnimation(.easeOut(duration: 0.4)) {
            threadsCardModel = ThreadsCardModelBuilder.removing(
                displayTerm: theme.displayTerm, from: threadsCardModel
            )
        }
    }
}
