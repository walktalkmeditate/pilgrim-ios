import SwiftUI

/// Walk summary section that renders the photo reliquary carousel.
///
/// Hides itself entirely if any of these conditions fail:
///   1. `UserPreferences.walkReliquaryEnabled` is OFF
///   2. `PermissionManager.standard.isPhotosGranted` is false
///   3. The walk has no GPS-tagged photos in its time window
///
/// When all three conditions are met, the section loads `PhotoCandidate`s via
/// `WalkPhotoMatcher.findCandidates(for:)` and presents the carousel.
struct PhotoReliquarySection: View {

    let walk: WalkInterface
    @Binding var candidates: [PhotoCandidate]

    @State private var isLoaded = false
    @State private var previewCandidate: PhotoCandidate?

    var body: some View {
        Group {
            if shouldRender, !candidates.isEmpty {
                content
            }
        }
        .onAppear {
            loadCandidatesIfNeeded()
        }
        .fullScreenCover(item: $previewCandidate) { candidate in
            PhotoPreviewSheet(
                candidate: candidate,
                onCommit: { commit(candidate) },
                onDismiss: { previewCandidate = nil }
            )
        }
    }

    private var shouldRender: Bool {
        UserPreferences.walkReliquaryEnabled.value
            && PermissionManager.standard.isPhotosGranted
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Reliquary")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
                .padding(.horizontal, Constants.UI.Padding.normal)
            PhotoCarouselView(
                candidates: $candidates,
                onCommit: { commit($0) },
                onPreview: { previewCandidate = $0 }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadCandidatesIfNeeded() {
        guard !isLoaded else { return }
        guard shouldRender else { return }
        isLoaded = true

        WalkPhotoMatcher.findCandidates(for: walk) { result in
            self.candidates = result
        }
    }

    /// Persist the pin/unpin state for `candidate` and optimistically update the local
    /// candidates array so the UI reflects the change immediately. Called from both the
    /// carousel (long-press → pin button) and the preview sheet ("Pin to map" button).
    private func commit(_ candidate: PhotoCandidate) {
        guard let walkID = walk.uuid else { return }
        guard let index = candidates.firstIndex(where: {
            $0.localIdentifier == candidate.localIdentifier
        }) else { return }

        let willBePinned = !candidates[index].isPinned

        candidates[index] = PhotoCandidate(
            localIdentifier: candidate.localIdentifier,
            capturedAt: candidate.capturedAt,
            capturedLat: candidate.capturedLat,
            capturedLng: candidate.capturedLng,
            isPinned: willBePinned
        )

        if willBePinned {
            DataManager.pinPhoto(
                to: walkID,
                localIdentifier: candidate.localIdentifier,
                capturedAt: candidate.capturedAt,
                capturedLat: candidate.capturedLat,
                capturedLng: candidate.capturedLng
            )
        } else {
            DataManager.unpinPhoto(walkID: walkID, localIdentifier: candidate.localIdentifier)
        }
    }
}
