import SwiftUI
import Photos

/// Full-screen preview overlay for a `PhotoCandidate`. Lazy-loads the highest-resolution
/// image PhotoKit can provide for the asset (full-res when available, downloaded from
/// iCloud if necessary).
///
/// Two corner buttons:
///   - Top-left: Pin to map / Unpin (calls `onCommit` then dismisses)
///   - Top-right: Open in Photos (launches Apple Photos via photos-redirect:// — lands at
///     the last-viewed screen, not the specific asset, due to iOS not exposing a public
///     URL scheme for individual PHAssets)
///
/// Swipe-down to dismiss. The captured `candidate` is a snapshot at the time the sheet was
/// presented; the parent's `onCommit` reads the canonical state from its candidates array
/// before persisting.
struct PhotoPreviewSheet: View {

    let candidate: PhotoCandidate
    var onCommit: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var image: UIImage?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                } else {
                    SwiftUI.ProgressView()
                        .tint(.parchment)
                }
            }
            .offset(y: dragOffset)

            VStack {
                HStack {
                    pinButton
                    Spacer()
                    openInPhotosButton
                }
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.top, Constants.UI.Padding.normal)
                Spacer()
            }
        }
        .onAppear { loadFullImage() }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private var pinButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onCommit()
            onDismiss()
        }) {
            Label(
                candidate.isPinned ? "Unpin" : "Pin to map",
                systemImage: candidate.isPinned ? "mappin.slash.circle.fill" : "mappin.circle.fill"
            )
            .font(Constants.Typography.button)
            .foregroundColor(.ink)
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.vertical, Constants.UI.Padding.small)
            .background(.regularMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var openInPhotosButton: some View {
        Button(action: {
            if let url = URL(string: "photos-redirect://") {
                UIApplication.shared.open(url)
            }
        }) {
            Label("Open in Photos", systemImage: "photo.on.rectangle")
                .font(Constants.Typography.button)
                .foregroundColor(.ink)
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.vertical, Constants.UI.Padding.small)
                .background(.regularMaterial)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadFullImage() {
        guard image == nil else { return }
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [candidate.localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            if let result {
                self.image = result
            }
        }
    }
}
