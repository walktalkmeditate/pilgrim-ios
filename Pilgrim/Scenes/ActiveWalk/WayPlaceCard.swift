import Photos
import SwiftUI

/// One card, five bodies. Lives in the bottom sheet; never a modal. Built
/// for a thumb and a glance while moving: the same header the preview
/// wears, one action per body, and a sideways swipe to let it go.
struct WayPlaceCard: View {
    let moment: WayMoment
    let mediaURL: URL?
    /// Metres from the walker's last fix; nil before the first fix.
    let distanceMeters: Double?
    let isPlaying: Bool
    let isPaused: Bool
    let elapsed: TimeInterval
    /// Amplitude bars for a voice, once its file has been read.
    let waveform: [Float]?
    /// True while the walker is recording their reply to this voice.
    let isRecordingReply: Bool
    let pendingCount: Int
    /// The walker's earlier reply to this voice, from a previous honoring of the same Way.
    let existingReply: URL?
    let rate: Float
    /// Degrees from the walker's heading to the moment, for the direction tick.
    let tick: Double?
    /// True while the map is showing this moment instead of the walker.
    let isFocused: Bool
    let onFly: () -> Void
    let onPlayPause: () -> Void
    let onSeek: (Double) -> Void
    let onCycleRate: () -> Void
    let onPlayReply: (URL) -> Void
    let onReply: () -> Void
    let onStopReply: () -> Void
    let onSit: (Int) -> Void
    let onDismiss: () -> Void
    /// Any deliberate touch: keeps an otherwise self-retiring card around.
    let onTouch: () -> Void

    @State private var confirmReplace = false
    @State private var dragOffset: CGFloat = 0

    private static let swipeToDismissPoints: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            HStack(alignment: .top) {
                // The header is the way to the place: one tap flies the map
                // there, the next brings it back to the walker.
                Button { onTouch(); onFly() } label: {
                    WayMomentHeader(
                        moment: moment,
                        subline: WayMomentHeader.relation(distanceMeters: distanceMeters, place: moment.place),
                        compact: true,
                        tick: tick
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFocused ? "Back to where you are" : "Show this place on the map")
                Spacer(minLength: Constants.UI.Padding.small)
                if pendingCount > 0 { queuePips }
                Button(action: onDismiss) {
                    Image(systemName: "xmark").foregroundColor(.fog)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }
            body(for: moment.kind)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
        .offset(x: dragOffset)
        .opacity(1 - min(0.6, abs(dragOffset) / 240))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if abs(value.translation.width) > abs(value.translation.height) { dragOffset = value.translation.width }
                }
                .onEnded { value in
                    if abs(value.translation.width) > Self.swipeToDismissPoints {
                        onDismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                    }
                }
        )
        .simultaneousGesture(TapGesture().onEnded { onTouch() })
    }

    /// One dot per waiting card, the same faded stone as their pins.
    private var queuePips: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(pendingCount, 4), id: \.self) { _ in
                Circle().fill(Color.stone.opacity(0.45)).frame(width: 5, height: 5)
            }
        }
        .padding(.top, Constants.UI.Padding.small)
        .accessibilityLabel("\(pendingCount) more waiting")
    }

    @ViewBuilder
    private func body(for kind: WayMomentKind) -> some View {
        switch kind {
        case .voice(_, let duration, _, _):
            voiceBody(duration: duration)
        case .photo(let media):
            WayPhotoPlate(media: media, fileURL: mediaURL, maxHeight: 110)
        case .rest:
            Text("A pause in their walk. The companion waits here with you.")
                .font(Constants.Typography.caption).foregroundColor(.fog)
        case .meditation(let minutes, _):
            HStack(spacing: Constants.UI.Padding.normal) {
                Button { onTouch(); onSit(minutes) } label: {
                    Text("Sit?").font(Constants.Typography.button).foregroundColor(.parchment)
                        .padding(.horizontal, Constants.UI.Padding.big).padding(.vertical, Constants.UI.Padding.small)
                        .background(Color.stone).cornerRadius(Constants.UI.CornerRadius.normal)
                }
                .accessibilityLabel("Sit here for \(minutes) minutes")
                Text("your soundscape holds while you sit")
                    .font(Constants.Typography.caption).foregroundColor(.fog)
            }
        case .waypoint:
            Text("A place they marked.")
                .font(Constants.Typography.caption).foregroundColor(.fog)
        }
    }

    // MARK: - Voice

    /// Transport on one line — play, the waveform you can scrub, the speed —
    /// and the reply on the next, so the two kinds of touch never sit
    /// shoulder to shoulder.
    @ViewBuilder
    private func voiceBody(duration: Double) -> some View {
        if isRecordingReply {
            HStack(spacing: Constants.UI.Padding.small) {
                RecordingPulse()
                Text("recording your reply here").font(Constants.Typography.body).foregroundColor(.ink)
                Spacer()
                Button { onStopReply() } label: {
                    Image(systemName: "stop.circle.fill").font(Constants.Typography.displayMedium).foregroundColor(.rust)
                }
                .accessibilityLabel("Stop recording your reply")
            }
        } else {
            if let line = moment.transcriptLine {
                Text("“\(line)”")
                    .font(Constants.Typography.body).italic().foregroundColor(.ink)
                    .lineLimit(2)
            }
            transportRow(duration: duration)
            replyRow
        }
    }

    private func transportRow(duration: Double) -> some View {
        let playing = isPlaying && !isPaused
        return HStack(alignment: .center, spacing: Constants.UI.Padding.small) {
            Button { onTouch(); onPlayPause() } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(Constants.Typography.displayMedium).foregroundColor(.stone)
            }
            .accessibilityLabel(playing ? "Pause their voice" : "Play their voice")
            VStack(alignment: .leading, spacing: 4) {
                if let waveform {
                    WaveformBarView(samples: waveform, progress: duration > 0 ? min(1, elapsed / duration) : 0, isPlaying: playing) { fraction in
                        onTouch(); onSeek(fraction)
                    }
                    .frame(height: 28)
                    .accessibilityLabel("Their voice; drag to move through it")
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Color.fog.opacity(0.15)).frame(height: 28)
                }
                Text("\(clock(elapsed)) / \(clock(duration))")
                    .font(Constants.Typography.caption).foregroundColor(.fog).monospacedDigit()
            }
            Button { onTouch(); onCycleRate() } label: {
                Text(rateLabel)
                    .font(Constants.Typography.caption)
                    .foregroundColor(rate > 1 ? .parchment : .stone)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(rate > 1 ? Color.stone : Color.stone.opacity(0.12))
                    .cornerRadius(4)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Playback speed, \(rateLabel)")
        }
    }

    private var replyRow: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            replyButton
            if let existingReply {
                Spacer()
                Button { onTouch(); onPlayReply(existingReply) } label: {
                    Label("your reply", systemImage: "play.circle")
                        .font(Constants.Typography.caption).foregroundColor(.stone)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Play your earlier reply")
            }
        }
    }

    @ViewBuilder
    private var replyButton: some View {
        if existingReply == nil {
            Button { onTouch(); onReply() } label: { replyPill("reply here") }
                .accessibilityLabel("Record a reply at this spot")
        } else {
            Button { onTouch(); confirmReplace = true } label: { replyPill("record again") }
                .accessibilityLabel("Record a new reply, replacing your earlier one")
                .confirmationDialog("Replace your earlier reply?", isPresented: $confirmReplace, titleVisibility: .visible) {
                    Button("Replace", role: .destructive, action: onReply)
                    Button("Keep it", role: .cancel) {}
                }
        }
    }

    private func replyPill(_ title: String) -> some View {
        Label(title, systemImage: "mic")
            .font(Constants.Typography.caption).foregroundColor(.stone)
            .padding(.horizontal, Constants.UI.Padding.normal).padding(.vertical, Constants.UI.Padding.small)
            .overlay(Capsule().stroke(Color.stone.opacity(0.5), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var rateLabel: String {
        rate.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fx", rate) : String(format: "%gx", rate)
    }

    private func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A single breathing dot: one boolean toggle under `.animation`, never a
/// mutated array inside a repeating animation.
private struct RecordingPulse: View {
    @State private var swelled = false

    var body: some View {
        Circle()
            .fill(Color.rust)
            .frame(width: 10, height: 10)
            .scaleEffect(swelled ? 1.25 : 0.85)
            .opacity(swelled ? 1 : 0.6)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: swelled)
            .onAppear { swelled = true }
            .accessibilityHidden(true)
    }
}

/// Small parchment-matted image; tap to open it whole.
struct WayPhotoPlate: View {
    let media: WayMedia
    let fileURL: URL?
    var maxHeight: CGFloat = 160
    @State private var image: UIImage?
    @State private var enlarged = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxHeight).cornerRadius(4)
                    .padding(6).background(Color.parchment).cornerRadius(6)
                    .onTapGesture { enlarged = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Enlarge photo")
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.parchment).frame(height: min(maxHeight, 120))
            }
        }
        // `fileURL` for a `.file` photo is nil on the first frame and filled
        // in by the host's own `.task(id:)` once the disk lookup resolves;
        // `.onAppear` alone would fire before that value ever arrives and
        // never re-fire when it does.
        .task(id: fileURL) { load() }
        .fullScreenCover(isPresented: $enlarged) {
            if let image {
                WayPhotoViewer(image: image) { enlarged = false }
            }
        }
    }

    private func load() {
        switch media {
        case .file:
            if let fileURL, let data = try? Data(contentsOf: fileURL) { image = UIImage(data: data) }
        case .photoAsset(let id):
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = assets.firstObject else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 900, height: 900),
                                                  contentMode: .aspectFit, options: options) { result, _ in
                guard let result else { return }
                DispatchQueue.main.async { image = result }
            }
        case .recording:
            break
        }
    }
}

struct HonorListeningChip: View {
    let elapsed: TimeInterval
    let isPaused: Bool
    let onPauseResume: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: "waveform").foregroundColor(.stone)
            Text(isPaused ? "paused" : "listening").font(Constants.Typography.caption).foregroundColor(.fog)
            Text("\(Int(elapsed) / 60):\(String(format: "%02d", Int(elapsed) % 60))")
                .font(Constants.Typography.caption).foregroundColor(.ink).monospacedDigit()
            Button(action: onPauseResume) { Image(systemName: isPaused ? "play.fill" : "pause.fill") }
                .accessibilityLabel(isPaused ? "Resume their voice" : "Pause their voice")
            Button(action: onSkip) { Image(systemName: "forward.end.fill") }
                .accessibilityLabel("Skip this voice")
        }
        .foregroundColor(.stone)
        .padding(.horizontal, Constants.UI.Padding.normal).padding(.vertical, 6)
        .background(Capsule().fill(Color.parchmentSecondary))
    }
}

struct HonorArrivalCardView: View {
    let card: HonorArrivalCard
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text(Self.title(for: card)).font(Constants.Typography.heading).foregroundColor(.ink)
            Text(card.stageName ?? card.wayTitle).font(Constants.Typography.body).foregroundColor(.fog)
            Text(Self.line(for: card)).font(Constants.Typography.caption).foregroundColor(.fog)
            Button("continue", action: onDismiss).font(Constants.Typography.button).foregroundColor(.stone)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
    }

    static func title(for card: HonorArrivalCard) -> String {
        card.stageName == nil ? "you walked their way" : "you walked the stage"
    }

    /// A stage counts places and kilometres; a shared walk counts voices and
    /// places, because a voice is what the other walker left.
    static func line(for card: HonorArrivalCard) -> String {
        var parts: [String] = []
        if card.stageName == nil, card.voicesHeard > 0 {
            parts.append(card.voicesHeard == 1 ? "one voice heard" : "\(card.voicesHeard) voices heard")
        }
        if card.placesPassed > 0 {
            parts.append(card.placesPassed == 1 ? "one place passed" : "\(card.placesPassed) places passed")
        }
        if card.stageName != nil {
            parts.append(StatsHelper.string(for: card.distanceWalkedMeters, unit: UnitLength.meters, type: .distance))
        }
        if parts.isEmpty { return card.stageName == nil ? "the whole way, in their steps" : "the whole stage" }
        return parts.joined(separator: " · ")
    }
}
