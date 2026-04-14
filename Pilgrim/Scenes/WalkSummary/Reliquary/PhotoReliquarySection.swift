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

    @State private var candidates: [PhotoCandidate] = []
    @State private var isLoaded = false

    var body: some View {
        Group {
            if shouldRender, !candidates.isEmpty {
                content
            }
        }
        .onAppear {
            loadCandidatesIfNeeded()
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
            Text("\(candidates.count) photo\(candidates.count == 1 ? "" : "s") from this walk")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
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
}
