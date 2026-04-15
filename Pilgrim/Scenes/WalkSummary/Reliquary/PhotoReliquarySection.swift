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

    /// Monotonic counter bumped on each fetch start. The completion
    /// handler drops results whose generation no longer matches, so if
    /// two fetches overlap (onAppear + a quickly-following scenePhase
    /// refresh, say), only the most recent one applies.
    @State private var fetchGeneration: UInt = 0

    /// True while a PHAsset fetch is in flight. Separate from
    /// `isLoaded` (which is a one-shot latch for the onAppear path) so
    /// the view can render a loading state between kickoff and
    /// completion.
    @State private var isFetching: Bool = false

    /// Flipped to true 300ms after a fetch begins. Matches Apple's
    /// loading-state patterns — fast fetches (cold cache under 300ms)
    /// skip the skeleton entirely so there's no distracting flicker,
    /// while slow fetches get a visible placeholder so the user knows
    /// something is happening. Reset to false when the fetch resolves.
    @State private var showLoadingSkeleton: Bool = false

    /// Drives the skeleton placeholders' opacity oscillation. Toggled
    /// to true in `onAppear` of the skeleton view; the `.animation`
    /// modifier on each placeholder carries the repeatForever curve.
    /// Single-bool toggle pattern (per project resource-safety rules)
    /// avoids SwiftUI re-diffing leaks.
    @State private var isShimmering: Bool = false

    /// Observed so the section re-renders when the app comes back from
    /// iOS Settings. Without this, a user who taps "Open Settings" in
    /// the permission-revoked prompt, grants Photos access, and returns
    /// to Pilgrim would still see the prompt — because the body has no
    /// reason to re-evaluate (no @State changed, onAppear doesn't fire
    /// for an already-visible view).
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isToggleOn {
                if isPermissionGranted {
                    if !candidates.isEmpty {
                        content
                            .transition(.opacity)
                    } else if showLoadingSkeleton {
                        loadingSkeleton
                            .transition(.opacity)
                    }
                    // else: either within the 300ms grace period or
                    // loaded with zero matching photos → render
                    // nothing so empty walks stay visually quiet.
                } else {
                    permissionRevokedPrompt
                }
            }
            // else: toggle OFF → feature is invisible
        }
        .animation(.easeInOut(duration: 0.3), value: candidates.isEmpty)
        .animation(.easeInOut(duration: 0.3), value: showLoadingSkeleton)
        .onAppear {
            loadCandidatesIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground transition (app switch / screen unlock /
            // returning from Settings). Only fetch when we actually
            // need fresh data — re-fetching on every foreground wipes
            // the in-memory pin state the user just created, because
            // WalkPhotoMatcher's `walk.walkPhotos` read can race the
            // CoreStore pin transaction and come back with
            // isPinned=false.
            //
            // The only cases where we genuinely need to act:
            //   - Gate is still open but candidates are empty → first
            //     grant from iOS Settings, load now.
            //   - Gate just closed while we were away → clear stale
            //     candidates so the parent's combinedAnnotations drops
            //     the map pins alongside the hidden carousel.
            // Otherwise (gate open + candidates populated): do nothing
            // and preserve the user's in-memory pin state.
            guard newPhase == .active else { return }
            if !shouldRender {
                if !candidates.isEmpty { candidates = [] }
            } else if candidates.isEmpty {
                reloadCandidates()
            }
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
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shown during the slow-fetch path (>300ms) so the user knows
    /// photos might be coming. Matches the real carousel's layout
    /// (heading + row of 88pt squares) so there's no jump when the
    /// real content replaces it. The placeholders shimmer via a
    /// single-bool opacity toggle — safe per the project's
    /// resource-safety rules on `.repeatForever`.
    @ViewBuilder
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            reliquaryHeading

            HStack(spacing: Constants.UI.Padding.small) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.parchmentSecondary)
                        .frame(width: 88, height: 88)
                        .opacity(isShimmering ? 0.45 : 0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            // Decorative — heading already announces the section.
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
            value: isShimmering
        )
        .onAppear {
            isShimmering = true
        }
        .onDisappear {
            isShimmering = false
        }
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
        reloadCandidates()
    }

    /// Force-refresh the carousel data. Used for scene-phase triggers,
    /// where the user may have granted or revoked permission in iOS
    /// Settings since the last load — the `isLoaded` latch must be
    /// bypassed so stale data doesn't survive a revoke/grant cycle.
    /// Also clears stale candidates when the gate has closed, which
    /// forces the parent view to re-derive `combinedAnnotations` so
    /// map photo pins hide alongside the carousel.
    private func reloadCandidates() {
        guard shouldRender else {
            if !candidates.isEmpty { candidates = [] }
            isFetching = false
            showLoadingSkeleton = false
            return
        }
        isLoaded = true
        fetchGeneration &+= 1
        let generation = fetchGeneration
        isFetching = true
        showLoadingSkeleton = false

        // Deferred skeleton — only shows if the fetch takes longer
        // than 300ms. Fast cold-cache hits skip the skeleton entirely
        // so there's no flicker on the happy path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard generation == self.fetchGeneration else { return }
            guard self.isFetching else { return }
            self.showLoadingSkeleton = true
        }

        WalkPhotoMatcher.findCandidates(for: walk) { result in
            guard generation == self.fetchGeneration else { return }
            self.candidates = result
            self.isFetching = false
            self.showLoadingSkeleton = false
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
