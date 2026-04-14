import SwiftUI
import Photos

/// Horizontal carousel of `PhotoCandidate` thumbnails for a walk's reliquary.
///
/// Pinned candidates display a small `mappin.fill` badge in the top-right corner.
/// Stage 4c renders thumbnails and badges only — long-press activation and tap-to-preview
/// gestures land in 4d/4f.
struct PhotoCarouselView: View {

    let candidates: [PhotoCandidate]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Constants.UI.Padding.small) {
                ForEach(candidates) { candidate in
                    PhotoThumbnailView(candidate: candidate)
                }
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
        }
        .frame(height: PhotoThumbnailView.size)
    }
}

/// A single thumbnail in the reliquary carousel. Loads its image asynchronously from
/// PhotoKit using the candidate's `localIdentifier`. Shows a pinned-badge overlay if the
/// candidate has been committed as a `WalkPhoto`.
struct PhotoThumbnailView: View {

    static let size: CGFloat = 88
    private static let cornerRadius: CGFloat = 8
    private static let badgeInset: CGFloat = 4

    let candidate: PhotoCandidate

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail
            if candidate.isPinned {
                pinnedBadge
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
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
            .padding(Self.badgeInset)
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
