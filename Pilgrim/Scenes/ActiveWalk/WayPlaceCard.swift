import Photos
import SwiftUI

/// One card, four bodies. Lives in the bottom sheet; never a modal.
struct WayPlaceCard: View {
    let moment: WayMoment
    let mediaURL: URL?
    let isPlaying: Bool
    let isPaused: Bool
    let elapsed: TimeInterval
    let pendingCount: Int
    /// The walker's earlier reply to this voice, from a previous honoring of the same Way.
    let existingReply: URL?
    let onPlayPause: () -> Void
    let onPlayReply: (URL) -> Void
    let onReply: () -> Void
    let onSit: (Int) -> Void
    let onDismiss: () -> Void
    @State private var confirmReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            HStack {
                Text(kicker).font(Constants.Typography.caption).foregroundColor(.fog)
                Spacer()
                if pendingCount > 0 {
                    Text("+\(pendingCount) more").font(Constants.Typography.caption).foregroundColor(.fog)
                }
                Button(action: onDismiss) { Image(systemName: "xmark").foregroundColor(.fog) }
                    .accessibilityLabel("Dismiss")
            }
            body(for: moment.kind)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
    }

    private var kicker: String {
        switch moment.kind {
        case .voice: return "spoken here"
        case .photo: return "what they saw here"
        case .rest(let m): return "they rested here \(m) minutes"
        case .meditation(let m, let est): return est ? "they sat here about \(m) minutes" : "they sat here for \(m) minutes"
        case .waypoint(let label, _): return label
        }
    }

    @ViewBuilder
    private func body(for kind: WayMomentKind) -> some View {
        switch kind {
        case .voice(_, let duration, _, _):
            HStack(spacing: Constants.UI.Padding.normal) {
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying && !isPaused ? "pause.circle" : "play.circle")
                        .font(Constants.Typography.displayMedium).foregroundColor(.stone)
                }
                .accessibilityLabel(isPlaying && !isPaused ? "Pause their voice" : "Play their voice")
                Text("\(Int(elapsed) / 60):\(String(format: "%02d", Int(elapsed) % 60)) / \(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))")
                    .font(Constants.Typography.timer).foregroundColor(.ink)
                Spacer()
                if existingReply == nil {
                    Button(action: onReply) {
                        Label("reply here", systemImage: "mic").font(Constants.Typography.button).foregroundColor(.stone)
                    }
                    .accessibilityLabel("Record a reply at this spot")
                } else {
                    Button { confirmReplace = true } label: {
                        Label("record again", systemImage: "mic").font(Constants.Typography.button).foregroundColor(.stone)
                    }
                    .accessibilityLabel("Record a new reply, replacing your earlier one")
                    .confirmationDialog("Replace your earlier reply?", isPresented: $confirmReplace, titleVisibility: .visible) {
                        Button("Replace", role: .destructive, action: onReply)
                        Button("Keep it", role: .cancel) {}
                    }
                }
            }
            if let existingReply {
                HStack(spacing: Constants.UI.Padding.small) {
                    Text("your reply").font(Constants.Typography.caption).foregroundColor(.fog)
                    Button { onPlayReply(existingReply) } label: {
                        Image(systemName: "play.circle").foregroundColor(.stone)
                    }
                    .accessibilityLabel("Play your earlier reply")
                }
            }
        case .photo(let media):
            WayPhotoPlate(media: media, fileURL: mediaURL)
        case .rest:
            EmptyView()
        case .meditation(let minutes, _):
            Button { onSit(minutes) } label: {
                Text("Sit?").font(Constants.Typography.button).foregroundColor(.parchment)
                    .padding(.horizontal, Constants.UI.Padding.big).padding(.vertical, Constants.UI.Padding.small)
                    .background(Color.stone).cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel("Sit here for \(minutes) minutes")
        case .waypoint:
            EmptyView()
        }
    }
}

/// Small parchment-matted image; tap to enlarge is a plain fullScreenCover.
struct WayPhotoPlate: View {
    let media: WayMedia
    let fileURL: URL?
    @State private var image: UIImage?
    @State private var enlarged = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 160).cornerRadius(4)
                    .padding(6).background(Color.parchment).cornerRadius(6)
                    .onTapGesture { enlarged = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Enlarge photo")
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.parchment).frame(height: 120)
            }
        }
        // `fileURL` for a `.file` photo is nil on the first frame and filled
        // in by the host's own `.task(id:)` once the disk lookup resolves;
        // `.onAppear` alone would fire before that value ever arrives and
        // never re-fire when it does.
        .task(id: fileURL) { load() }
        .fullScreenCover(isPresented: $enlarged) {
            ZStack { Color.black.ignoresSafeArea(); if let image { Image(uiImage: image).resizable().scaledToFit() } }
                .onTapGesture { enlarged = false }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close photo")
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
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 600, height: 600),
                                                  contentMode: .aspectFit, options: options) { result, _ in
                guard let result else { return }
                // PhotoKit promises no queue for an opportunistic request's
                // second delivery, and `image` is SwiftUI state.
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
                .font(Constants.Typography.caption).foregroundColor(.ink)
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
            Text("you walked their way").font(Constants.Typography.heading).foregroundColor(.ink)
            Text(card.wayTitle).font(Constants.Typography.body).foregroundColor(.fog)
            Text(line).font(Constants.Typography.caption).foregroundColor(.fog)
            Button("continue", action: onDismiss).font(Constants.Typography.button).foregroundColor(.stone)
        }
        .padding(Constants.UI.Padding.normal)
        .background(RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal).fill(Color.parchmentSecondary))
    }

    private var line: String {
        var parts: [String] = []
        if card.voicesHeard > 0 { parts.append(card.voicesHeard == 1 ? "one voice heard" : "\(card.voicesHeard) voices heard") }
        if card.placesPassed > 0 { parts.append(card.placesPassed == 1 ? "one place passed" : "\(card.placesPassed) places passed") }
        return parts.isEmpty ? "the whole way, in their steps" : parts.joined(separator: " · ")
    }
}
