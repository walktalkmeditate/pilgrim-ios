import SwiftUI

/// Medium-detent confirmation sheet presented before a `.pilgrim` export.
/// Shows walk count + date range, and — only when the user has at least
/// one pinned reliquary photo — a toggle to opt into embedding photos
/// in the archive.
///
/// The sheet doesn't touch `PilgrimPackageBuilder` itself; it surfaces a
/// user decision and passes it back via `onExport(includePhotos:)`. The
/// caller (Stage 5e: `DataSettingsView`) is responsible for kicking off
/// the build and handling the `skippedPhotoCount` in the result.
///
/// The photo toggle defaults ON when visible — the user has already
/// opted into the reliquary feature and pinned these photos, so including
/// them in a share is the reasonable default. Explicit opt-out is one tap.
struct ExportConfirmationSheet: View {

    let walkCount: Int
    let dateRangeText: String
    let pinnedPhotoCount: Int
    let estimatedPhotoSizeBytes: Int
    let onCancel: () -> Void
    let onExport: (_ includePhotos: Bool) -> Void

    @State private var includePhotos = true

    private var showsPhotoToggle: Bool { pinnedPhotoCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Spacer(minLength: 0)
            buttonBar
        }
        .background(Color.parchment)
    }

    // MARK: - Sections

    private var header: some View {
        Text("Export Walks")
            .font(Constants.Typography.heading)
            .foregroundColor(.ink)
            .padding(.top, Constants.UI.Padding.big)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.big) {
            summary
            if showsPhotoToggle {
                photoToggleSection
            }
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.top, Constants.UI.Padding.big)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            Text(walkCountText)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            Text(dateRangeText)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    private var photoToggleSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Toggle(isOn: $includePhotos) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include pinned photos")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text(photoSizeText)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.stone)

            Text("Photos travel with the file. Anyone you share it with will see them as map markers.")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    private var buttonBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
            }

            Spacer()

            Button(action: { onExport(showsPhotoToggle && includePhotos) }) {
                Text("Export")
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .padding(.horizontal, Constants.UI.Padding.big)
                    .padding(.vertical, 12)
                    .background(Color.stone)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Constants.UI.Padding.normal)
        .padding(.vertical, Constants.UI.Padding.normal)
    }

    // MARK: - Formatting

    private var walkCountText: String {
        "\(walkCount) walk\(walkCount == 1 ? "" : "s")"
    }

    private var photoSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        let sizeString = formatter.string(fromByteCount: Int64(estimatedPhotoSizeBytes))
        let photoNoun = pinnedPhotoCount == 1 ? "photo" : "photos"
        return "\(pinnedPhotoCount) \(photoNoun) · ≈\(sizeString)"
    }
}

#if DEBUG
#Preview("With photos") {
    ExportConfirmationSheet(
        walkCount: 23,
        dateRangeText: "March 2024 – April 2026",
        pinnedPhotoCount: 18,
        estimatedPhotoSizeBytes: 1_440_000,
        onCancel: {},
        onExport: { _ in }
    )
    .presentationDetents([.medium])
}

#Preview("No photos") {
    ExportConfirmationSheet(
        walkCount: 7,
        dateRangeText: "January 2026 – April 2026",
        pinnedPhotoCount: 0,
        estimatedPhotoSizeBytes: 0,
        onCancel: {},
        onExport: { _ in }
    )
    .presentationDetents([.medium])
}

#Preview("Single walk, single photo") {
    ExportConfirmationSheet(
        walkCount: 1,
        dateRangeText: "April 14, 2026",
        pinnedPhotoCount: 1,
        estimatedPhotoSizeBytes: 80_000,
        onCancel: {},
        onExport: { _ in }
    )
    .presentationDetents([.medium])
}
#endif
