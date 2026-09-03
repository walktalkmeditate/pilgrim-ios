import SwiftUI

/// A pin tapped on the overview, before Begin: what they did here, how far
/// along their way and at what hour, then the thing itself — the photo,
/// the voice with its waveform, the place they marked, the sitting. The
/// walk's own cards live in the sheet; this is the fuller, standing-still
/// version of the same moment.
struct WayMomentPreview: View {
    let way: Way
    let moment: WayMoment
    let mediaURL: URL?

    private let alongTheWay: String

    @StateObject private var player = AudioPlayerModel()
    @State private var waveform: [Float]?

    init(way: Way, moment: WayMoment, mediaURL: URL?) {
        self.way = way
        self.moment = moment
        self.mediaURL = mediaURL
        alongTheWay = Self.alongTheWay(way: way, moment: moment)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                header
                content
            }
            .padding(Constants.UI.Padding.normal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.parchment)
        .onDisappear { player.stop() }
        .task(id: mediaURL) { await loadWaveform() }
    }

    // MARK: - Header

    private var header: some View {
        WayMomentHeader(moment: moment, subline: alongTheWay)
    }

    /// "1.2 km along their way · 8:41 AM · Rúa do Franco": the moment's place
    /// on the line, the hour it happened in the walk's own time zone, and the
    /// street the sharer's page names when it has one.
    private static func alongTheWay(way: Way, moment: WayMoment) -> String {
        let distance = StatsHelper.string(for: moment.frac * way.totalDistanceMeters, unit: UnitLength.meters, type: .distance)
        let elapsed = WayGeometry(route: way.route).elapsed(atFrac: moment.frac)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = way.tzIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        var parts = ["\(distance) along their way", formatter.string(from: way.departedAt.addingTimeInterval(elapsed))]
        if let place = moment.place, !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Body per kind

    @ViewBuilder
    private var content: some View {
        switch moment.kind {
        case .voice(_, let duration, let kind, _):
            voiceContent(duration: duration, kind: kind)
        case .photo(let media):
            VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                WayPhotoPlate(media: media, fileURL: mediaURL, maxHeight: 360)
                Text("tap the photo to see it whole").font(Constants.Typography.caption).foregroundColor(.fog)
            }
        case .waypoint:
            Text("A place they marked. When you walk it, it rises as a card as you reach it.")
                .font(Constants.Typography.body).foregroundColor(.ink)
        case .rest:
            Text("A pause in their walk. The companion will wait here with you.")
                .font(Constants.Typography.body).foregroundColor(.ink)
        case .meditation:
            Text("A sitting. When you walk it, the way will offer you the same sitting here.")
                .font(Constants.Typography.body).foregroundColor(.ink)
        }
    }

    private func voiceContent(duration: Double, kind: VoiceKind) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            if let mediaURL {
                HStack(spacing: Constants.UI.Padding.small) {
                    Button { player.toggle(url: mediaURL) } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(Constants.Typography.displayMedium).foregroundColor(.stone)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause their voice" : "Play their voice")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind == .ambient ? "as it sounded" : "in their own voice")
                            .font(Constants.Typography.body).foregroundColor(.ink)
                        Text(clock(duration)).font(Constants.Typography.caption).foregroundColor(.fog)
                    }
                    Spacer()
                    Button { player.cycleSpeed() } label: {
                        Text(speedLabel)
                            .font(Constants.Typography.caption)
                            .foregroundColor(player.playbackSpeed > 1 ? .parchment : .stone)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(player.playbackSpeed > 1 ? Color.stone : Color.stone.opacity(0.12))
                            .cornerRadius(4)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Playback speed, \(speedLabel)")
                }
                if let waveform {
                    WaveformBarView(samples: waveform, progress: player.progress, isPlaying: player.isPlaying) { fraction in
                        if player.currentPath != mediaURL.path { player.play(url: mediaURL) }
                        player.seek(to: fraction)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Color.fog.opacity(0.15)).frame(height: 32)
                }
                HStack {
                    Text(clock(player.currentTime)).monospacedDigit()
                    Spacer()
                    Text(clock(player.totalDuration > 0 ? player.totalDuration : duration)).monospacedDigit()
                }
                .font(Constants.Typography.caption).foregroundColor(.fog)
            } else {
                HStack(spacing: Constants.UI.Padding.small) {
                    Image(systemName: "waveform.slash").foregroundColor(.fog)
                    Text("their voice is still on its way here").font(Constants.Typography.body).foregroundColor(.fog)
                }
            }
            Text(kind == .ambient
                 ? "When you walk it, this plays once, softly, as you pass."
                 : "When you walk it, this plays where they stood to say it.")
                .font(Constants.Typography.caption).foregroundColor(.fog)
        }
    }

    private var speedLabel: String {
        player.playbackSpeed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fx", player.playbackSpeed)
            : String(format: "%gx", player.playbackSpeed)
    }

    private func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func loadWaveform() async {
        guard case .voice = moment.kind, let mediaURL else { return }
        waveform = await Task.detached(priority: .utility) {
            WaveformGenerator.generateSamples(from: mediaURL)
        }.value
    }
}
