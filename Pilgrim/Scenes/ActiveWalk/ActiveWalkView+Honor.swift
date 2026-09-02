import SwiftUI

extension ActiveWalkView {

    /// The Way's card, sitting directly above the stats sheet in both sheet
    /// states: it is the walker's turn to answer, not ambience to be covered.
    /// Nothing at all in the other two modes.
    @ViewBuilder
    func honorCardLayer(bottomInset: CGFloat) -> some View {
        if viewModel.mode == .honor {
            HonorCardHost(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, bottomInset + Constants.UI.Padding.small)
                // The layer spans the screen; with no card on it, every touch
                // belongs to the map underneath.
                .allowsHitTesting(viewModel.isShowingHonorCard)
        }
    }

    /// A tapped Way pin opens that moment's card, jumping any queue. The five
    /// `way*` kinds are the only ones carrying a moment id; every other pin
    /// belongs to `handleAnnotationTap`.
    func showWayCard(for annotation: PilgrimAnnotation) {
        let momentID: String
        switch annotation.kind {
        case .wayVoice(let id, _), .wayPhoto(let id), .wayRest(let id, _),
             .waySit(let id, _), .wayWaypoint(let id, _, _):
            momentID = id
        default:
            return
        }
        guard let moment = viewModel.way?.moments.first(where: { $0.id == momentID }) else { return }
        viewModel.showCard(for: moment)
    }
}

/// The arrival card, or the top place card. Its own view rather than a
/// property of `ActiveWalkView` for two reasons: it observes the shared voice
/// player so the card's elapsed time actually ticks, and it holds the card's
/// resolved files in state so the disk lookups behind them happen once per
/// card instead of on every body evaluation of the walk screen.
struct HonorCardHost: View {

    @ObservedObject var viewModel: ActiveWalkViewModel
    @ObservedObject private var voicePlayer = WayVoicePlayer.shared
    @State private var mediaURL: URL?
    @State private var existingReply: URL?

    var body: some View {
        Group {
            // Dismissal retires the card through its own flag: `honorArrival`
            // carries the companion delta the coordinator persists when the
            // walk is saved, which may be long after this tap.
            if let card = viewModel.honorArrival, !viewModel.honorArrivalCardDismissed {
                HonorArrivalCardView(card: card) { viewModel.honorArrivalCardDismissed = true }
            } else if let moment = viewModel.honorCards.first, let way = viewModel.way {
                WayPlaceCard(
                    moment: moment,
                    way: way,
                    mediaURL: mediaURL,
                    isPlaying: viewModel.activeVoice == moment,
                    isPaused: viewModel.isVoicePaused,
                    elapsed: voicePlayer.elapsedSeconds,
                    pendingCount: max(0, viewModel.honorCards.count - 1),
                    existingReply: existingReply,
                    onPlayPause: { viewModel.togglePlayback(of: moment) },
                    onPlayReply: { url in viewModel.playReply(url: url) },
                    onReply: { viewModel.replyHere(to: moment) },
                    onSit: { minutes in viewModel.startMeditation(minutes: minutes) },
                    onDismiss: { viewModel.dismissTopCard() }
                )
                .task(id: lookupKey(for: moment)) { resolveFiles(for: moment) }
            }
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
    }

    /// Re-resolves when the card changes, and once more when a recording
    /// ends — that is when a fresh reply becomes readable.
    private func lookupKey(for moment: WayMoment) -> String {
        "\(moment.id)|\(viewModel.isRecordingVoice)"
    }

    private func resolveFiles(for moment: WayMoment) {
        mediaURL = momentMediaURL(for: moment)
        existingReply = moment.isVoice ? viewModel.existingReplyURL(for: moment) : nil
    }

    private func momentMediaURL(for moment: WayMoment) -> URL? {
        switch moment.kind {
        case .voice(_, _, _, let media), .photo(let media):
            return viewModel.mediaURL(for: media)
        default:
            return nil
        }
    }
}
