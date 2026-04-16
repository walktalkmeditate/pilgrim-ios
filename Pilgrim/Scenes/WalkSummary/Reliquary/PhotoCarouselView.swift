import SwiftUI
import Photos

/// Horizontal carousel of `PhotoCandidate` thumbnails for a walk's reliquary.
///
/// One photo at a time can be in the "activated" state (long-pressed). While activated,
/// a centered `mappin.circle.fill` icon overlays the thumbnail; tapping that icon commits
/// (or unpins) via the `onCommit` callback. Tapping the photo itself routes to the
/// full-screen preview via the `onPreview` callback — both when activated (which also
/// dismisses the activation) and when inactive (a plain tap-to-preview).
///
/// Persistence happens upstream in `PhotoReliquarySection.commit(_:)` — the carousel only
/// owns the activation/visual layer.
struct PhotoCarouselView: View {

    @Binding var candidates: [PhotoCandidate]
    @Binding var activePhotoID: String?
    var onCommit: (PhotoCandidate) -> Void = { _ in }
    var onPreview: (PhotoCandidate) -> Void = { _ in }

    @State private var activeID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Constants.UI.Padding.small) {
                ForEach(candidates) { candidate in
                    PhotoThumbnailView(
                        candidate: candidate,
                        isActive: activeID == candidate.localIdentifier,
                        onLongPress: { activate(candidate) },
                        onPinTap: { commit(candidate) },
                        onPhotoTap: { dismissAndPreview(candidate) }
                    )
                    .id(candidate.localIdentifier)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Constants.UI.Padding.normal)
        }
        .scrollPosition(id: $activePhotoID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .onScrollPhaseChange { _, newPhase in
            // The plan dictates that scrolling the carousel dismisses any active
            // long-press activation. .interacting fires the moment the user starts
            // a drag, so the activation goes away before the user even reaches a
            // new item.
            if newPhase == .interacting && activeID != nil {
                activeID = nil
            }
        }
        .frame(height: PhotoThumbnailView.size + 8)
    }

    private func activate(_ candidate: PhotoCandidate) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeID = candidate.localIdentifier
    }

    private func commit(_ candidate: PhotoCandidate) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        activeID = nil
        onCommit(candidate)
    }

    private func dismissAndPreview(_ candidate: PhotoCandidate) {
        activeID = nil
        onPreview(candidate)
    }
}

/// A single thumbnail in the reliquary carousel. Loads its image asynchronously from
/// PhotoKit using the candidate's `localIdentifier`.
///
/// Three visual states:
///   - inactive + unpinned: just the thumbnail
///   - inactive + pinned: thumbnail with a small `mappin.fill` badge in the top-right corner
///   - active: thumbnail scaled up with a centered pin icon overlay (pin or unpin variant
///     depending on current state). Tapping the icon commits; tapping the photo dismisses
///     activation and routes to the preview.
struct PhotoThumbnailView: View {

    static let size: CGFloat = 88
    private static let cornerRadius: CGFloat = 8
    private static let badgeInset: CGFloat = 4
    private static let activeScale: CGFloat = 1.05
    private static let centerIconSize: CGFloat = 32
    private static let centerIconBackgroundSize: CGFloat = 44

    let candidate: PhotoCandidate
    let isActive: Bool
    var onLongPress: () -> Void = {}
    var onPinTap: () -> Void = {}
    var onPhotoTap: () -> Void = {}

    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        thumbnail
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(alignment: .topTrailing) {
                if !isActive && candidate.isPinned {
                    pinnedBadge
                        .padding(Self.badgeInset)
                }
            }
            .overlay {
                if isActive {
                    centeredPinButton
                }
            }
            .scaleEffect(isActive ? Self.activeScale : 1.0)
            // Honor Reduce Motion: when enabled, the activation state still
            // flips (centered pin button appears, scale changes) but without
            // the spring animation. Same pattern WalkSummaryView uses for
            // its share-card reveal.
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                value: isActive
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onPhotoTap()
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                onLongPress()
            }
            .onAppear { loadImage() }
            // VoiceOver: collapse the thumbnail into a single accessible
            // element with a descriptive label and direct pin/unpin
            // action. Sighted users use long-press → tap pin button;
            // VoiceOver users skip the activation step entirely via the
            // custom action.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint("Shows photo at full size")
            .accessibilityAction(named: candidate.isPinned ? "Unpin from map" : "Pin to map") {
                onPinTap()
            }
    }

    private var accessibilityLabelText: String {
        let dateText = candidate.capturedAt.formatted(date: .abbreviated, time: .shortened)
        if candidate.isPinned {
            return "Photo, captured \(dateText), pinned to map"
        }
        return "Photo, captured \(dateText)"
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size, height: Self.size)
        } else {
            Color.parchmentSecondary
                .frame(width: Self.size, height: Self.size)
        }
    }

    private var pinnedBadge: some View {
        Image(systemName: "mappin.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.parchment)
            .padding(5)
            .background(Color.stone)
            .clipShape(Circle())
            // Decorative — the parent thumbnail's accessibilityLabel
            // already conveys "pinned to map". Hide from VoiceOver to
            // avoid a duplicate "Pin" announcement.
            .accessibilityHidden(true)
    }

    private var centeredPinButton: some View {
        Button(action: onPinTap) {
            Image(systemName: candidate.isPinned ? "mappin.slash.circle.fill" : "mappin.circle.fill")
                .font(.system(size: Self.centerIconSize, weight: .semibold))
                .foregroundColor(.stone)
                .frame(width: Self.centerIconBackgroundSize, height: Self.centerIconBackgroundSize)
                .background(Color.parchment.opacity(0.85))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func loadImage() {
        guard image == nil else { return }
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [candidate.localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return }

        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: Self.size * scale, height: Self.size * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            // PHImageManager's resultHandler runs on an arbitrary serial queue when
            // isSynchronous is false. Marshal to main before mutating @State.
            guard let result else { return }
            DispatchQueue.main.async {
                self.image = result
            }
        }
    }
}
