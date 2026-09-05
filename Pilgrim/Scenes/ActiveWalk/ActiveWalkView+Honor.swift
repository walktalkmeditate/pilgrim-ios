import SwiftUI

extension ActiveWalkView {

    /// The Way's card, sitting directly above the stats sheet in both sheet
    /// states: it is the walker's turn to answer, not ambience to be covered.
    /// Nothing at all in the other two modes.
    @ViewBuilder
    func honorCardLayer(bottomInset: CGFloat, onSit: @escaping (Int) -> Void) -> some View {
        // Gated on the walk being active, like the ambient overlay and the
        // turning watermark: a pin tap before Begin must not open a card
        // whose play button would mark a voice heard with no player behind it.
        if viewModel.mode == .honor && viewModel.status.isActiveStatus {
            HonorCardHost(viewModel: viewModel, onSit: onSit)
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
        // The card LAYER is already gated on an active walk, but the queue
        // behind it is not: a pin tapped on the overview map before Begin
        // used to sit in `honorCards` and ambush the walker with someone
        // else's card the moment they started walking.
        guard viewModel.status.isActiveStatus, let momentID = annotation.kind.wayMomentID else { return }
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
    /// Owned by `ActiveWalkView`: starts the engine's meditation AND presents
    /// `MeditationView` via its own `@State showMeditation`, which lives on
    /// the parent, not here — a card-only `startMeditation(minutes:)` call
    /// starts the session headless, with no view ever clearing `isMeditating`.
    let onSit: (Int) -> Void
    @State private var mediaURL: URL?
    @State private var existingReply: URL?
    @State private var waveform: [Float]?

    var body: some View {
        Group {
            // Dismissal retires the card through its own flag: `honorArrival`
            // carries the companion delta the coordinator persists when the
            // walk is saved, which may be long after this tap.
            if let card = viewModel.honorArrival, !viewModel.honorArrivalCardDismissed {
                HonorArrivalCardView(card: card) { viewModel.honorArrivalCardDismissed = true }
            } else if let moment = viewModel.honorCards.first {
                let isPlaying = viewModel.activeVoice == moment
                WayPlaceCard(
                    moment: moment,
                    isStage: viewModel.way?.isPilgrimageStage == true,
                    mediaURL: mediaURL,
                    distanceMeters: viewModel.distanceToMoment(moment),
                    isPlaying: isPlaying,
                    isPaused: viewModel.isVoicePaused,
                    // The player's clock is shared across every voice; a card
                    // whose voice isn't the one playing must not show its tick.
                    elapsed: isPlaying ? voicePlayer.elapsedSeconds : 0,
                    waveform: waveform,
                    isRecordingReply: viewModel.isRecordingVoice && viewModel.pendingReplyOrigin == moment,
                    pendingCount: max(0, viewModel.honorCards.count - 1),
                    existingReply: existingReply,
                    rate: viewModel.voiceRate,
                    tick: viewModel.relativeBearing(to: moment),
                    isFocused: viewModel.honorFocus != nil,
                    onFly: { viewModel.toggleFocus(on: moment) },
                    onPlayPause: { viewModel.togglePlayback(of: moment) },
                    onSeek: { fraction in viewModel.seekVoice(moment, toFraction: fraction) },
                    onCycleRate: { viewModel.cycleVoiceRate() },
                    onPlayReply: { url in viewModel.playReply(url: url) },
                    onReply: { viewModel.replyHere(to: moment) },
                    onStopReply: { viewModel.toggleVoiceRecording() },
                    onSit: onSit,
                    onDismiss: { viewModel.dismissTopCard() },
                    onTouch: { viewModel.touchCard(moment) }
                )
                .id(moment.id)
                .task(id: lookupKey(for: moment)) { await resolveFiles(for: moment) }
            }
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
    }

    /// Re-resolves when the card changes, and again once a recording has
    /// finished saving — the completed count, not the recording flag: the
    /// file only becomes readable after the flag has already gone back to
    /// false, so keying on the flag left a fresh reply hidden until the card
    /// was closed and reopened.
    private func lookupKey(for moment: WayMoment) -> String {
        "\(moment.id)|\(viewModel.completedRecordingCount)"
    }

    private func resolveFiles(for moment: WayMoment) async {
        let url = momentMediaURL(for: moment)
        mediaURL = url
        existingReply = moment.isVoice ? viewModel.existingReplyURL(for: moment) : nil
        // The host outlives each card (only the card carries `.id`), so a
        // stale waveform must be cleared before the next one is read.
        waveform = nil
        guard moment.isVoice, let url else { return }
        let samples = await Task.detached(priority: .utility) { WaveformGenerator.generateSamples(from: url) }.value
        guard !Task.isCancelled else { return }
        waveform = samples
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
