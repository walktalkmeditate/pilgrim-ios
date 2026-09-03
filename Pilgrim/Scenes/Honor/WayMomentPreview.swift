import SwiftUI

/// A pin tapped on the overview, before Begin: the photo plate or the voice
/// itself, so a walker can look and listen before deciding to walk it. The
/// walk's own cards live in the sheet; this is the same content in a
/// half-height sheet of its own.
struct WayMomentPreview: View {
    let moment: WayMoment
    let mediaURL: URL?

    @ObservedObject private var player = WayVoicePlayer.shared
    /// Whether this preview started the voice that is playing; a stop on
    /// dismiss must never silence something else.
    @State private var startedHere = false

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            Text(kicker).font(Constants.Typography.caption).foregroundColor(.fog)
            content
            Spacer(minLength: 0)
        }
        .padding(Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parchment)
        .onDisappear {
            if startedHere { player.stop() }
        }
    }

    private var kicker: String {
        switch moment.kind {
        case .voice: return "spoken here"
        case .photo: return "what they saw here"
        case .rest(let minutes): return "they rested here \(minutes) minutes"
        case .meditation(let minutes, let isEstimate):
            return isEstimate ? "they sat here about \(minutes) minutes" : "they sat here for \(minutes) minutes"
        case .waypoint(let label, _): return label
        }
    }

    @ViewBuilder
    private var content: some View {
        switch moment.kind {
        case .voice(_, let duration, let kind, _):
            if let mediaURL {
                voiceRow(url: mediaURL, duration: duration, kind: kind)
            } else {
                Text("their voice is still on its way here")
                    .font(Constants.Typography.caption).foregroundColor(.fog)
            }
        case .photo(let media):
            WayPhotoPlate(media: media, fileURL: mediaURL)
        case .waypoint(_, let icon):
            HStack(spacing: Constants.UI.Padding.small) {
                Image(systemName: UIImage(systemName: icon) == nil ? "mappin" : icon).foregroundColor(.stone)
                Text("a place they marked").font(Constants.Typography.body).foregroundColor(.ink)
            }
        case .rest, .meditation:
            EmptyView()
        }
    }

    private var isPlayingThis: Bool { startedHere && player.isPlayingWayVoice }

    private func voiceRow(url: URL, duration: Double, kind: VoiceKind) -> some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            Button {
                if isPlayingThis {
                    player.stop()
                    startedHere = false
                } else {
                    player.play(url: url, volume: ActiveWalkViewModel.voiceVolume(for: kind))
                    startedHere = true
                }
            } label: {
                Image(systemName: isPlayingThis ? "pause.circle" : "play.circle")
                    .font(Constants.Typography.displayMedium).foregroundColor(.stone)
            }
            .accessibilityLabel(isPlayingThis ? "Stop their voice" : "Play their voice")
            Text("\(clock(isPlayingThis ? player.elapsedSeconds : 0)) / \(clock(duration))")
                .font(Constants.Typography.timer).foregroundColor(.ink)
        }
    }

    private func clock(_ seconds: Double) -> String {
        "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
    }
}
