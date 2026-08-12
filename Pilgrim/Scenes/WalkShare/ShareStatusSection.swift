import SwiftUI

/// The Share button through all its states — idle, in-flight progress
/// (photo export, POST, media PUTs), the success/partial result card, and
/// error retry. Lives in its own file to keep WalkShareView under the
/// type-body-length ceiling (mirrors InteractiveShareSection).
struct ShareStatusSection: View {

    @ObservedObject var viewModel: WalkShareViewModel
    let onOpenPreview: (String) -> Void

    @ViewBuilder
    var body: some View {
        switch viewModel.shareState {
        case .idle:
            primaryButton("Share Walk") {
                viewModel.beginShare()
            }

        case .uploading:
            progressRow("Sharing...", font: Constants.Typography.button)

        case .preparingPhotos(let done, let total):
            progressRow("Preparing photos… \(done)/\(total)")

        case .photosDropped(let prepared, let dropped):
            droppedPhotosPrompt(prepared: prepared, dropped: dropped)

        case .uploadingMedia(let completed, let total):
            progressRow(
                "Carrying your walk… \(completed)/\(total)",
                subtitle: "keep Pilgrim open while your walk uploads"
            )

        case .success(let url):
            sharedCard(url: url) { EmptyView() }

        case .partial(let url, let failedCount):
            sharedCard(url: url) {
                VStack(spacing: Constants.UI.Padding.small) {
                    Text("\(failedCount) file\(failedCount == 1 ? "" : "s") didn't make it — they'll show as unavailable on the page.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.rust)
                        .multilineTextAlignment(.center)

                    if viewModel.repairUnavailable {
                        Text("These files can no longer be carried — the walk's recordings have changed.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                            .multilineTextAlignment(.center)
                    } else {
                        Button {
                            viewModel.beginRetry()
                        } label: {
                            Text("Carry the missing files")
                                .font(Constants.Typography.button)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.stone)
                                .foregroundColor(.parchment)
                                .cornerRadius(Constants.UI.CornerRadius.small)
                        }
                    }
                }
            }

        case .error(let message):
            VStack(spacing: Constants.UI.Padding.small) {
                Text(message)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.rust)
                    .multilineTextAlignment(.center)

                primaryButton("Try Again") {
                    viewModel.beginShare()
                }
            }
        }
    }

    private var routePreview: some View {
        ShareRouteThumbnail(routeData: viewModel.walk.routeData)
    }

    /// Shared by `.uploading`, `.preparingPhotos`, and `.uploadingMedia` —
    /// same spinner-row chrome, different label. `subtitle` adds a second,
    /// de-emphasized line below the spinner row (only `.uploadingMedia`
    /// uses it today, for the "keep Pilgrim open" reminder).
    private func progressRow(_ text: String, subtitle: String? = nil, font: Font = Constants.Typography.caption) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: Constants.UI.Padding.small) {
                SwiftUI.ProgressView()
                    .tint(.parchment)
                Text(text)
                    .font(font)
                    .foregroundColor(.parchment)
            }
            if let subtitle {
                Text(subtitle)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.stone.opacity(0.6))
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    /// `.photosDropped`'s pre-POST consent pause: some requested photos
    /// didn't export (iCloud-only assets that never downloaded, deletions
    /// mid-export), so the walker chooses whether to proceed without them
    /// or hold off — nothing has POSTed yet, so both choices are still free.
    private func droppedPhotosPrompt(prepared: Int, dropped: Int) -> some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Text("\(dropped) of \(prepared + dropped) photo\(dropped == 1 ? "" : "s") couldn't be prepared — they may still be waiting in iCloud.")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)

            primaryButton("Share without them") {
                viewModel.continueShareWithoutDroppedPhotos()
            }

            Button {
                viewModel.cancelDroppedPhotoShare()
            } label: {
                Text("Don't share yet")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The "page is live" card shared by `.success` and `.partial` — the
    /// route thumbnail, the Shared badge, and the expiry note are identical
    /// either way; `extra` inserts `.partial`'s missing-files notice between
    /// the expiry note and the "View scroll" link.
    @ViewBuilder
    private func sharedCard(url: String, @ViewBuilder extra: () -> some View) -> some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Button {
                onOpenPreview(url)
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

            Text("Returns to the trail on \(viewModel.formattedExpiry)")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .italic()

            extra()

            Button {
                onOpenPreview(url)
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
        .disabled(!viewModel.canShare)
    }
}

// MARK: - Route Thumbnail

/// The small route-shape preview shown both while sharing (`WalkShareView`)
/// and once shared (`ShareStatusSection`'s card) — same `RouteShapeView`,
/// frame, background, and corner radius either way, so one source exists.
struct ShareRouteThumbnail: View {
    let routeData: [RouteDataSampleInterface]

    var body: some View {
        RouteShapeView(routeData: routeData)
            .frame(height: 200)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
    }
}
