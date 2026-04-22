import SwiftUI

struct WalkShareView: View {

    @StateObject private var viewModel: WalkShareViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPodcastCard = false
    @State private var showPreview = false
    @State private var revealTask: Task<Void, Never>?
    @State private var podcastRevealTask: Task<Void, Never>?
    @StateObject private var webViewLoaderHolder = WebViewLoaderHolder()
    @State private var previewURL: String?

    let walk: WalkInterface
    let pinnedPhotos: [PhotoCandidate]

    init(walk: WalkInterface, pinnedPhotos: [PhotoCandidate] = []) {
        self.walk = walk
        self.pinnedPhotos = pinnedPhotos
        _viewModel = StateObject(wrappedValue: WalkShareViewModel(walk: walk, pinnedPhotos: pinnedPhotos))
    }

    private var isShared: Bool {
        if case .success = viewModel.shareState { return true }
        return false
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.big) {
                    if isShared {
                        shareButton
                        if showPodcastCard,
                           PodcastSubmissionService.shared.isEligible(walk: walk),
                           case .success(let url) = viewModel.shareState {
                            PodcastSubmissionView(walk: walk, shareURL: url)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    } else {
                        routePreview
                        statToggles
                        journalSection
                        expiryPicker
                        shareButton
                    }
                }
                .padding(Constants.UI.Padding.normal)
            }
            .background(Color.parchment)
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
                    if !isShared {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(.stone)
                    }
                }
            }
        }
        // Reveal the podcast card after the ritual modal dismisses, not at
        // the moment of share success. The previous 800ms-after-success
        // trigger collided with the ritual's own reveal — the card animated
        // invisibly behind the modal, and its haptic doubled up with the
        // ritual's. Tying the reveal to `showPreview` going true → false
        // gives the card a visible fade-in and separates the two haptics.
        .onChange(of: showPreview) { wasShowing, isShowing in
            guard wasShowing, !isShowing,
                  !showPodcastCard,
                  isShared,
                  PodcastSubmissionService.shared.isEligible(walk: walk) else { return }
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
                Text("Expires \(expiryDateFormatted)")
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

    private var expiryDateFormatted: String {
        Self.expiryFormatter.string(from: viewModel.expiryDate)
    }

    private static let expiryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        switch viewModel.shareState {
        case .idle:
            primaryButton("Share Walk") {
                Task { await viewModel.share() }
            }

        case .uploading:
            HStack(spacing: Constants.UI.Padding.small) {
                SwiftUI.ProgressView()
                    .tint(.parchment)
                Text("Sharing...")
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.stone.opacity(0.6))
            .cornerRadius(Constants.UI.CornerRadius.normal)

        case .success(let url):
            VStack(spacing: Constants.UI.Padding.normal) {
                Button {
                    openPreview(url: url)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        routePreview
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.fog.opacity(0.4))
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View shared walk page")
                .accessibilityHint("Opens the scroll of your shared walk")

                HStack(spacing: 6) {
                    Text("Shared")
                        .font(Constants.Typography.body)
                        .foregroundColor(.stone)
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.moss)
                }

                Text("Returns to the trail on \(expiryDateFormatted)")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .italic()

                Button {
                    openPreview(url: url)
                } label: {
                    Text("View scroll")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(Constants.UI.Padding.normal)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)

        case .error(let message):
            VStack(spacing: Constants.UI.Padding.small) {
                Text(message)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.rust)
                    .multilineTextAlignment(.center)

                primaryButton("Try Again") {
                    Task { await viewModel.share() }
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Constants.Typography.button)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.stone)
                .foregroundColor(.parchment)
                .cornerRadius(Constants.UI.CornerRadius.normal)
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
        guard case .uploading = old, case .success(let url) = new else { return }
        guard let parsedURL = URL(string: url) else { return }

        webViewLoaderHolder.create(url: parsedURL)
        previewURL = url

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
