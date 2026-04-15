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

    /// Double-tap guard for the Export button. The sheet's dismiss
    /// animation leaves the Export button hit-testable for ~0.3s, and a
    /// fast double-tap would fire `onExport` twice — in Stage 5e that
    /// would start two concurrent `PilgrimPackageBuilder.build()` calls
    /// racing on the same archive URL. Same pattern as `PhotoPreviewSheet`
    /// in Stage 4.
    @State private var hasCommitted = false

    private var showsPhotoToggle: Bool { pinnedPhotoCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            // ScrollView so the middle content can expand for Dynamic Type
            // accessibility sizes and still fit on small screens (iPhone SE)
            // at the medium detent. SwiftUI's `.medium` is a fixed ~50%
            // of screen height — it doesn't auto-grow with content — so
            // without a ScrollView the privacy note or toggle subtitle
            // would clip at the bottom on XXL text sizes. Header and
            // button bar stay pinned outside the scroll region.
            ScrollView {
                content
            }
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
            Text(Self.walkCountText(for: walkCount))
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
                    Text(Self.photoSizeText(
                        photoCount: pinnedPhotoCount,
                        bytes: estimatedPhotoSizeBytes
                    ))
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
            Button(role: .cancel, action: onCancel) {
                Text("Cancel")
                    .font(Constants.Typography.body)
                    .foregroundColor(.fog)
                    // Apple HIG specifies a 44pt minimum tap target for
                    // comfortable touch interaction. Plain Text bounds
                    // would give ~40x20pt — hard to tap reliably. Padding
                    // extends the hit area without visually changing the
                    // button's appearance.
                    .padding(.horizontal, Constants.UI.Padding.normal)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }

            Spacer()

            Button(action: exportTapped) {
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
        .padding(.vertical, Constants.UI.Padding.small)
    }

    private func exportTapped() {
        // The sheet's dismiss animation leaves this button hit-testable
        // for a few frames after the first tap. Without this guard, a
        // fast double-tap would fire onExport twice — in Stage 5e that
        // means two concurrent PilgrimPackageBuilder.build() calls
        // racing on the same archive URL.
        guard !hasCommitted else { return }
        hasCommitted = true
        onExport(Self.effectiveIncludePhotos(
            pinnedPhotoCount: pinnedPhotoCount,
            userToggle: includePhotos
        ))
    }

    // MARK: - Testable helpers

    /// Returns `"1 walk"` / `"2 walks"` with correct singular/plural. Static
    /// so it can be unit tested without instantiating the view.
    static func walkCountText(for count: Int) -> String {
        "\(count) walk\(count == 1 ? "" : "s")"
    }

    /// Returns `"18 photos · ≈1.4 MB"` for a typical case. Uses
    /// `ByteCountFormatter` with `.file` style (decimal KB/MB) to match
    /// iOS conventions and the plan's "≈1.4 MB" wording. Static for
    /// unit testability.
    static func photoSizeText(photoCount: Int, bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        let sizeString = formatter.string(fromByteCount: Int64(bytes))
        let photoNoun = photoCount == 1 ? "photo" : "photos"
        return "\(photoCount) \(photoNoun) · ≈\(sizeString)"
    }

    /// Resolves the final value passed to `onExport`. When the user has
    /// zero pinned photos, the toggle row is hidden and the user never
    /// sees the choice — we must never pass `true` to the builder in
    /// that case, regardless of what `@State includePhotos` holds.
    /// Extracting this guarantees the invariant survives refactors.
    static func effectiveIncludePhotos(
        pinnedPhotoCount: Int,
        userToggle: Bool
    ) -> Bool {
        pinnedPhotoCount > 0 && userToggle
    }
}

#if DEBUG
// Each preview wraps the sheet in a `.sheet(isPresented:)` host so the
// `.presentationDetents([.medium])` modifier takes effect (it's a no-op
// when the view is rendered as a root view outside a sheet context).
// This makes the preview a faithful simulation of how the sheet will
// render on-device inside `DataSettingsView.exportData()`.
private struct ExportConfirmationSheetPreviewHost: View {
    let walkCount: Int
    let dateRangeText: String
    let pinnedPhotoCount: Int
    let estimatedPhotoSizeBytes: Int

    @State private var isPresented = true

    var body: some View {
        Color.parchment.ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                ExportConfirmationSheet(
                    walkCount: walkCount,
                    dateRangeText: dateRangeText,
                    pinnedPhotoCount: pinnedPhotoCount,
                    estimatedPhotoSizeBytes: estimatedPhotoSizeBytes,
                    onCancel: { isPresented = false },
                    onExport: { _ in isPresented = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }
}

#Preview("With photos") {
    ExportConfirmationSheetPreviewHost(
        walkCount: 23,
        dateRangeText: "March 2024 – April 2026",
        pinnedPhotoCount: 18,
        estimatedPhotoSizeBytes: 1_440_000
    )
}

#Preview("No photos") {
    ExportConfirmationSheetPreviewHost(
        walkCount: 7,
        dateRangeText: "January 2026 – April 2026",
        pinnedPhotoCount: 0,
        estimatedPhotoSizeBytes: 0
    )
}

#Preview("Single walk, single photo") {
    ExportConfirmationSheetPreviewHost(
        walkCount: 1,
        dateRangeText: "April 14, 2026",
        pinnedPhotoCount: 1,
        estimatedPhotoSizeBytes: 80_000
    )
}
#endif
