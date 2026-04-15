import SwiftUI

/// Walk summary section that renders the photo reliquary carousel.
///
/// Three render states gated by the user's settings + iOS permission:
///   1. Toggle OFF → renders nothing (feature is invisible until opt-in)
///   2. Toggle ON, permission granted, candidates exist → renders carousel
///   3. Toggle ON, permission granted, no candidates → renders nothing
///      (no point showing an empty reliquary)
///   4. Toggle ON, permission revoked in iOS Settings → renders a gentle
///      prompt with a Settings deep link, so the user knows why their
///      reliquary disappeared and can recover with one tap.
///
/// When state 2 is active, the section loads `PhotoCandidate`s via
/// `WalkPhotoMatcher.findCandidates(for:)` and presents the carousel.
struct PhotoReliquarySection: View {

    let walk: WalkInterface
    @Binding var candidates: [PhotoCandidate]
    @Binding var activePhotoID: String?

    @State private var isLoaded = false
    @State private var previewCandidate: PhotoCandidate?

    var body: some View {
        Group {
            if isToggleOn {
                if isPermissionGranted {
                    if !candidates.isEmpty {
                        content
                    }
                    // else: no candidates → render nothing (empty
                    // walks shouldn't show empty section noise)
                } else {
                    permissionRevokedPrompt
                }
            }
            // else: toggle OFF → feature is invisible
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

    private var isToggleOn: Bool {
        UserPreferences.walkReliquaryEnabled.value
    }

    private var isPermissionGranted: Bool {
        PermissionManager.standard.isPhotosGranted
    }

    private var shouldRender: Bool {
        isToggleOn && isPermissionGranted
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            reliquaryHeading
            PhotoCarouselView(
                candidates: $candidates,
                activePhotoID: $activePhotoID,
                onCommit: { commit($0) },
                onPreview: { previewCandidate = $0 }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown when the reliquary toggle is ON but Photos permission has
    /// been revoked in iOS Settings. The toggle stays ON in
    /// UserPreferences (the user opted in once and we don't want to
    /// silently flip it back), but the carousel can't load candidates
    /// without permission. Surfacing a quiet prompt with a Settings
    /// deep link tells the user why their reliquary disappeared and
    /// gives them a one-tap recovery path.
    @ViewBuilder
    private var permissionRevokedPrompt: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            reliquaryHeading

            Text("Photo access was revoked. Grant Photo Library access in iOS Settings to see photos from this walk.")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .padding(.horizontal, Constants.UI.Padding.normal)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openIOSSettings) {
                Text("Open Settings")
                    .font(Constants.Typography.button)
                    .foregroundColor(.stone)
                    .padding(.horizontal, Constants.UI.Padding.normal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var reliquaryHeading: some View {
        Text("Reliquary")
            .font(Constants.Typography.heading)
            .foregroundColor(.ink)
            .padding(.horizontal, Constants.UI.Padding.normal)
            // VoiceOver: marks this as a heading so users navigating
            // by heading rotor can jump directly to the reliquary
            // section, matching how walk summary's other section
            // titles are exposed.
            .accessibilityAddTraits(.isHeader)
    }

    private func openIOSSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
