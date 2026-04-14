import SwiftUI
import Photos

/// Horizontal carousel of `PhotoCandidate` thumbnails for a walk's reliquary.
///
/// One photo at a time can be in the "activated" state (long-pressed). While activated,
/// a centered `mappin.circle.fill` icon overlays the thumbnail. Tapping the icon commits
/// (or unpins) via the `onCommit` callback. Tapping the photo itself (not the icon)
/// dismisses activation and routes to the full-screen preview via the `onPreview` callback.
///
/// Persistence happens upstream in `PhotoReliquarySection.commit(_:)` — the carousel only
/// owns the activation/visual layer.
struct PhotoCarouselView: View {

    @Binding var candidates: [PhotoCandidate]
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
                }
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
            .contentShape(Rectangle())
            .onTapGesture {
                if isActive {
                    onPhotoTap()
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                onLongPress()
            }
            .onAppear { loadImage() }
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
            if let result {
                self.image = result
            }
        }
    }
}
