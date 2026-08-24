import SwiftUI

// MARK: - Thought Threads card glue
//
// Extracted from `WalkSummaryView.swift` like the +Map extension, to keep
// the main type body under SwiftLint's type_body_length limit. Stored
// state stays in the struct; everything else lives here.

/// The single `.task(id:)` key for the threads-card load — transcriptions
/// changing and the reload generation bumping (sheet dismissals) are the
/// only two reasons to reload, so folding both into one Equatable key lets
/// SwiftUI's own `.task(id:)` cancellation replace three previously
/// uncoordinated triggers.
struct ThreadsCardReloadKey: Equatable {
    let transcriptions: [UUID: String]
    let generation: Int
}

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

    /// `.task(id:)` cancels a superseded call before it reaches the guards
    /// below, closing the race between uncoordinated triggers. The
    /// changeCount check closes a second race this cancellation can't: a
    /// release or welcome-back (`releaseTheme`, Settings) landing on
    /// `ReleasedThreadsStore` while THIS load's own await is in flight,
    /// which isn't a superseding reload at all — nothing bumped
    /// `threadsReloadGeneration` — just a decision that made this result
    /// stale mid-flight. Applying it anyway would resurrect a chip the
    /// walker just released as a zombie whose tap opens an empty history.
    func loadThreadsCard() async {
        guard showsThreadsCard else { return }
        let changeCountBefore = ReleasedThreadsStore.shared.changeCount
        let result = await ThreadsCardLoader.load(walk: walk, transcriptions: transcriptions)
        guard !Task.isCancelled else { return }
        guard ReleasedThreadsStore.shared.changeCount == changeCountBefore else { return }
        threadsCardModel = result
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
