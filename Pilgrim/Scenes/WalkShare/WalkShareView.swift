import SwiftUI

struct WalkShareView: View {

    @StateObject private var viewModel: WalkShareViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPodcastCard = false
    @State private var showPreview = false
    @State private var revealTask: Task<Void, Never>?
    @State private var podcastRevealTask: Task<Void, Never>?
    @State private var ritualDidFire = false
    @StateObject private var webViewLoaderHolder = WebViewLoaderHolder()
    @State private var previewURL: String?

    let walk: WalkInterface
    let pinnedPhotos: [PhotoCandidate]

    init(walk: WalkInterface, pinnedPhotos: [PhotoCandidate] = []) {
        self.walk = walk
        self.pinnedPhotos = pinnedPhotos
        _viewModel = StateObject(wrappedValue: WalkShareViewModel(walk: walk, pinnedPhotos: pinnedPhotos))
    }

    private var isShared: Bool { viewModel.isShared }

    /// The POST already created a live page and, once media starts landing,
    /// partial progress is recorded server-side — the sheet must not be
    /// abandonable mid-flight. Gates both the toolbar Cancel and
    /// `.interactiveDismissDisabled` below.
    private var isShareInFlight: Bool {
        switch viewModel.shareState {
        case .preparingPhotos, .uploading, .uploadingMedia: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.big) {
                    if isShared {
                        ShareStatusSection(viewModel: viewModel, onOpenPreview: openPreview)
                        if showPodcastCard,
                           PodcastSubmissionService.shared.isEligible(walk: walk),
                           case .success(let url) = viewModel.shareState {
                            PodcastSubmissionView(walk: walk, shareURL: url)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    } else {
                        routePreview
                        // A share is already in flight once the POST has landed a
                        // live page and media PUTs are streaming — editing toggles,
                        // the journal, or expiry now would desync the payload
                        // already sent from what these controls show (wrong-slot
                        // audio, a broken trim promise, undeclared PUTs). Disabling
                        // at this container level freezes every input inside in one
                        // place instead of chasing each control individually.
                        Group {
                            statToggles
                            InteractiveShareSection(viewModel: viewModel)
                            journalSection
                            expiryPicker
                        }
                        .disabled(isShareInFlight)
                        ShareStatusSection(viewModel: viewModel, onOpenPreview: openPreview)
                    }
                }
                .padding(Constants.UI.Padding.normal)
            }
            .canvasBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isShared ? "Walk Shared" : "Share Walk")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isShared {
                        Button("Done") { dismiss() }
                            .foregroundColor(.stone)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isShared && !isShareInFlight {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.stone)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isShareInFlight)
        // Reveal the podcast card after the ritual modal dismisses, not at
        // the moment of share success. The previous 800ms-after-success
        // trigger collided with the ritual's own reveal — the card animated
        // invisibly behind the modal, and its haptic doubled up with the
        // ritual's. Tying the reveal to `showPreview` going true → false
        // gives the card a visible fade-in and separates the two haptics.
        .onChange(of: showPreview) { wasShowing, isShowing in
            // Only reveal after a FRESH-share modal dismiss (ritualDidFire).
            // Cache-hit re-entry via the walk summary's tappable URL also
            // dismisses the modal via showPreview true → false, and without
            // this gate the podcast card would spuriously appear on every
            // re-view of a walk that was shared weeks ago.
            guard wasShowing, !isShowing,
                  ritualDidFire,
                  !showPodcastCard,
                  isShared,
                  PodcastSubmissionService.shared.isEligible(walk: walk) else { return }
            ritualDidFire = false
            podcastRevealTask?.cancel()
            podcastRevealTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showPodcastCard = true
                    }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
        }
        .fullScreenCover(isPresented: $showPreview, onDismiss: {
            webViewLoaderHolder.clear()
            previewURL = nil
        }) {
            if let loader = webViewLoaderHolder.loader, let url = previewURL {
                WalkSharePreviewView(
                    loader: loader,
                    shareURL: url,
                    onDismiss: { showPreview = false }
                )
            }
        }
        .background(
            Group {
                if let loader = webViewLoaderHolder.loader, !showPreview {
                    WebViewRepresentable(webView: loader.webView)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .allowsHitTesting(false)
                }
            }
        )
        .onChange(of: viewModel.shareState) { oldValue, newValue in
            triggerRitualIfNeeded(old: oldValue, new: newValue)
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
            podcastRevealTask?.cancel()
            podcastRevealTask = nil
            // Guard against iOS versions / scene configs where onDisappear
            // fires on the parent while the cover is still presented (e.g.,
            // app backgrounded with modal open). Clearing the loader mid-
            // presentation would leave the cover rendering an empty view.
            if !showPreview {
                webViewLoaderHolder.clear()
            }
        }
    }

    // MARK: - Route Preview

    private var routePreview: some View {
        let points = viewModel.walk.routeData
        return RouteShapeView(routeData: points)
            .frame(height: 200)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    // MARK: - Stat Toggles

    private var statToggles: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            sectionLabel("Share these details")

            StatToggleRow(
                title: "Distance",
                value: viewModel.formattedDistance,
                isOn: $viewModel.toggleDistance
            )
            StatToggleRow(
                title: "Duration",
                value: viewModel.formattedDuration,
                isOn: $viewModel.toggleDuration
            )
            StatToggleRow(
                title: "Elevation",
                value: viewModel.formattedElevation,
                isOn: $viewModel.toggleElevation
            )
            StatToggleRow(
                title: "Walk / Meditation / Talk",
                value: viewModel.formattedActivityBreakdown,
                isOn: $viewModel.toggleActivityBreakdown
            )
            StatToggleRow(
                title: "Steps",
                value: viewModel.formattedSteps,
                isOn: $viewModel.toggleSteps
            )
            if viewModel.hasWaypoints {
                StatToggleRow(
                    title: "Waypoints",
                    value: "\(viewModel.waypointCount) \(viewModel.waypointCount == 1 ? "place" : "places") you marked",
                    isOn: $viewModel.includeWaypoints
                )
            }
            if viewModel.hasPinnedPhotos {
                VStack(alignment: .leading, spacing: 4) {
                    StatToggleRow(
                        title: "Reliquary Photos",
                        value: "\(viewModel.pinnedPhotoCount) \(viewModel.pinnedPhotoCount == 1 ? "photo" : "photos") you pinned",
                        isOn: $viewModel.includePhotos
                    )
                    if viewModel.includePhotos {
                        Text("Photos will be visible to anyone with the link.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                            .padding(.horizontal, Constants.UI.Padding.normal)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.includePhotos)
            }
        }
    }

    // MARK: - Journal

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            sectionLabel("Reflection")

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.journal)
                    .font(Constants.Typography.body)
                    .frame(minHeight: 80)
                    .padding(Constants.UI.Padding.small)
                    .scrollContentBackground(.hidden)
                    .background(Color.parchmentSecondary)
                    .cornerRadius(Constants.UI.CornerRadius.small)
                    .onChange(of: viewModel.journal) { _, newValue in
                        if newValue.count > 140 {
                            viewModel.journal = String(newValue.prefix(140))
                        }
                    }

                if viewModel.journal.isEmpty {
                    Text("\u{201C}A few words about this walk...")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog)
                        .padding(.horizontal, Constants.UI.Padding.normal)
                        .padding(.vertical, Constants.UI.Padding.normal)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Text("\(viewModel.journal.count) / 140")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Expiry Picker

    private var expiryPicker: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            sectionLabel("This walk lives for")

            HStack(spacing: Constants.UI.Padding.small) {
                ForEach(WalkShareViewModel.ExpiryOption.allCases, id: \.rawValue) { option in
                    expiryButton(option)
                }
            }

            HStack {
                Spacer()
                Text("Expires \(viewModel.formattedExpiry)")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Spacer()
            }
        }
    }

    private func expiryButton(_ option: WalkShareViewModel.ExpiryOption) -> some View {
        let isSelected = viewModel.selectedExpiry == option
        return Button {
            viewModel.selectedExpiry = option
        } label: {
            ZStack {
                // CJK glyphs require system font — Cormorant Garamond has no kanji coverage
                Text(option.kanji)
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(isSelected ? .parchment.opacity(0.12) : .fog.opacity(0.06))

                Text(option.label)
                    .font(Constants.Typography.caption)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.stone : Color.parchmentSecondary)
            .foregroundColor(isSelected ? .parchment : .fog)
            .cornerRadius(Constants.UI.CornerRadius.small)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Constants.Typography.micro)
            .foregroundColor(.fog)
            .tracking(1.5)
    }

    private func openPreview(url: String) {
        guard let parsedURL = URL(string: url) else { return }
        // If the user taps to open during the 800ms ritual beat, cancel the
        // pending reveal so its haptic + redundant showPreview assignment
        // don't fire on an already-open modal.
        revealTask?.cancel()
        revealTask = nil
        if webViewLoaderHolder.loader == nil {
            webViewLoaderHolder.create(url: parsedURL)
        }
        previewURL = url
        showPreview = true
    }

    private func triggerRitualIfNeeded(
        old: WalkShareViewModel.ShareState,
        new: WalkShareViewModel.ShareState
    ) {
        guard case .success(let url) = new else { return }
        switch old {
        case .uploading, .uploadingMedia: break
        default: return
        }
        guard let parsedURL = URL(string: url) else { return }

        webViewLoaderHolder.create(url: parsedURL)
        previewURL = url
        ritualDidFire = true

        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showPreview = true
            }
        }
    }
}

// MARK: - WebViewLoaderHolder

@MainActor
private final class WebViewLoaderHolder: ObservableObject {
    @Published var loader: WebViewLoader?

    func create(url: URL) {
        loader = WebViewLoader(url: url)
    }

    func clear() {
        loader = nil
    }
}

// MARK: - Stat Toggle Row

private struct StatToggleRow: View {
    let title: String
    let value: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                if let value {
                    Text(value)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.moss)
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, 10)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.small)
    }
}
