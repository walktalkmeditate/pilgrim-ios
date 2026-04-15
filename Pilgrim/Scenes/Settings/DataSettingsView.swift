import SwiftUI
import CoreStore
import UniformTypeIdentifiers
import ZIPFoundation

struct DataSettingsView: View {

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isExportingRecordings = false
    @State private var showDocumentPicker = false
    @State private var exportURL: URL?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var recordingCount = 0

    /// Driven by `exportData()` — when non-nil, the export confirmation
    /// sheet is presented. Stage 5e's entry point: the user taps
    /// "Export My Data", we compute the summary parameters from the DB
    /// (walk count, date range, pinned photo count, estimated size),
    /// store them here, and `.sheet(item:)` presents the sheet.
    @State private var exportConfirmData: ExportConfirmData?

    /// Set by the most recent `performExport` success. Consumed by
    /// `cleanupExport()` to surface a post-share alert when any photos
    /// were skipped. Kept separate from the sheet-item state so the
    /// alert can fire AFTER the share sheet is dismissed.
    @State private var lastSkippedPhotoCount = 0

    private var isBusy: Bool { isExporting || isImporting || isExportingRecordings }

    /// Identifiable snapshot of the data the export confirmation sheet
    /// needs. Computed on the main thread from CoreStore fetches and
    /// frozen at the moment the user taps "Export My Data" — the sheet
    /// displays exactly what we observed, even if the DB changes while
    /// the sheet is up.
    private struct ExportConfirmData: Identifiable {
        let id = UUID()
        let walkCount: Int
        let dateRangeText: String
        let pinnedPhotoCount: Int
        let estimatedPhotoSizeBytes: Int
    }

    /// Per-photo byte estimate for the size label. Matches the plan's
    /// "~80 KB average" target set in Stage 5c's Core Image pipeline.
    /// A static const so it can be audited in one place if the target
    /// ever changes.
    private static let estimatedBytesPerPhoto = 80_000

    var body: some View {
        List {
            Section {
                Button(action: exportData) {
                    HStack {
                        Text("Export My Data")
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        if isExporting {
                            SwiftUI.ProgressView()
                                .tint(.stone)
                        }
                    }
                }
                .disabled(isBusy)

                Button(action: { showDocumentPicker = true }) {
                    HStack {
                        Text("Import Data")
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        if isImporting {
                            SwiftUI.ProgressView()
                                .tint(.stone)
                        }
                    }
                }
                .disabled(isBusy)
            } header: {
                Text("Walks")
                    .font(Constants.Typography.caption)
            } footer: {
                Text("Export creates a .pilgrim archive with all your walks, transcriptions, and settings. Import restores walks from a .pilgrim file.")
                    .font(Constants.Typography.caption)
            }

            Section {
                NavigationLink(destination: JourneyViewerView()) {
                    Text("View My Journey")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
            } footer: {
                Text("Opens view.pilgrimapp.org and renders all your walks in the browser. Your data stays on your device — nothing is uploaded.")
                    .font(Constants.Typography.caption)
            }

            if recordingCount > 0 {
                Section {
                    Button(action: exportRecordings) {
                        HStack {
                            Text("Export Recordings")
                                .font(Constants.Typography.body)
                                .foregroundColor(.ink)
                            Spacer()
                            Text("\(recordingCount)")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                            if isExportingRecordings {
                                SwiftUI.ProgressView()
                                    .tint(.stone)
                            }
                        }
                    }
                    .disabled(isBusy)
                } header: {
                    Text("Audio")
                        .font(Constants.Typography.caption)
                } footer: {
                    Text("Exports all voice recording audio files as a zip archive. These are not included in the data export.")
                        .font(Constants.Typography.caption)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Data")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { cleanupExport() } }
        )) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(item: $exportConfirmData) { data in
            ExportConfirmationSheet(
                walkCount: data.walkCount,
                dateRangeText: data.dateRangeText,
                pinnedPhotoCount: data.pinnedPhotoCount,
                estimatedPhotoSizeBytes: data.estimatedPhotoSizeBytes,
                onCancel: { exportConfirmData = nil },
                onExport: { includePhotos in
                    exportConfirmData = nil
                    performExport(includePhotos: includePhotos)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDocumentPicker) {
            PilgrimDocumentPicker { url in
                importData(from: url)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            recordingCount = DataManager.recordingFileCount()
        }
    }

    // MARK: - Export Data

    /// Entry point for the "Export My Data" button. Computes the summary
    /// parameters (walk count, date range, pinned photo count, estimated
    /// size), then either presents the confirmation sheet — which in
    /// turn calls `performExport(includePhotos:)` — or short-circuits
    /// with a "no walks" alert.
    private func exportData() {
        // Re-entry guard: the `isBusy` button disable chain covers the
        // build phase itself, but there are two gaps where isExporting
        // is false and the button is enabled:
        //   1. Confirmation sheet is up, waiting for user choice.
        //   2. Build succeeded and the share sheet is visible.
        // A rapid second tap in either gap would either swap the
        // confirmation sheet mid-presentation (jarring) or queue a new
        // sheet on top of the share sheet (stacked modals). Bail out
        // if either state is active.
        guard exportConfirmData == nil, exportURL == nil else { return }

        guard let data = computeExportConfirmData() else {
            alertTitle = "Export Failed"
            alertMessage = "No walks found to export."
            showAlert = true
            return
        }
        exportConfirmData = data
    }

    /// Kicked off from the confirmation sheet's `onExport` callback.
    /// Forwards the user's `includePhotos` choice to the builder,
    /// stashes any skipped-photo count for the post-share alert, and
    /// presents the share sheet on success.
    private func performExport(includePhotos: Bool) {
        isExporting = true
        PilgrimPackageBuilder.build(includePhotos: includePhotos) { result in
            isExporting = false
            switch result {
            case .success(let buildResult):
                lastSkippedPhotoCount = buildResult.skippedPhotoCount
                exportURL = buildResult.url
            case .failure(let error):
                alertTitle = "Export Failed"
                alertMessage = describeError(error)
                showAlert = true
            }
        }
    }

    /// Gathers the summary parameters the confirmation sheet needs.
    /// Returns nil when there are no walks (caller short-circuits with
    /// the "no walks" alert and never presents the sheet — avoids the
    /// confusing "0 walks" display).
    ///
    /// All fetches are CoreStore read operations on the main stack;
    /// they're fast at any reasonable walk count and don't need to be
    /// dispatched to a background queue.
    private func computeExportConfirmData() -> ExportConfirmData? {
        let walkCount = (try? DataManager.dataStack.fetchCount(From<Walk>())) ?? 0
        guard walkCount > 0 else { return nil }

        let earliest = (try? DataManager.dataStack.fetchOne(
            From<Walk>().orderBy(.ascending(\._startDate))
        ))?.startDate
        let latest = (try? DataManager.dataStack.fetchOne(
            From<Walk>().orderBy(.descending(\._startDate))
        ))?.startDate

        let dateRangeText: String
        if let earliest, let latest {
            dateRangeText = ExportDateRangeFormatter.format(
                earliest: earliest,
                latest: latest
            )
        } else {
            dateRangeText = ""
        }

        let pinnedPhotoCount = (try? DataManager.dataStack.fetchCount(From<WalkPhoto>())) ?? 0
        let estimatedPhotoSizeBytes = pinnedPhotoCount * Self.estimatedBytesPerPhoto

        return ExportConfirmData(
            walkCount: walkCount,
            dateRangeText: dateRangeText,
            pinnedPhotoCount: pinnedPhotoCount,
            estimatedPhotoSizeBytes: estimatedPhotoSizeBytes
        )
    }

    // MARK: - Import Data

    private func importData(from url: URL) {
        isImporting = true
        let accessing = url.startAccessingSecurityScopedResource()
        PilgrimPackageImporter.importPackage(from: url) { result in
            if accessing { url.stopAccessingSecurityScopedResource() }
            isImporting = false
            switch result {
            case .success(let count):
                alertTitle = "Import Complete"
                alertMessage = "\(count) walk\(count == 1 ? "" : "s") imported."
                showAlert = true
            case .failure(let error):
                alertTitle = "Import Failed"
                alertMessage = describeError(error)
                showAlert = true
            }
        }
    }

    // MARK: - Export Recordings

    private func exportRecordings() {
        isExportingRecordings = true
        DispatchQueue.global(qos: .userInitiated).async {
            let url = buildRecordingsArchive()
            DispatchQueue.main.async {
                isExportingRecordings = false
                if let url = url {
                    exportURL = url
                } else {
                    alertTitle = "Export Failed"
                    alertMessage = "Failed to create recordings archive."
                    showAlert = true
                }
            }
        }
    }

    private func buildRecordingsArchive() -> URL? {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = docs.appendingPathComponent("Recordings")

        guard fm.fileExists(atPath: recordingsDir.path) else { return nil }

        let timeCode = CustomDateFormatting.backupTimeCode(forDate: Date())
        let archiveURL = fm.temporaryDirectory
            .appendingPathComponent("pilgrim-recordings-\(timeCode).zip")

        try? fm.removeItem(at: archiveURL)

        do {
            try fm.zipItem(at: recordingsDir, to: archiveURL, shouldKeepParent: false)
            return archiveURL
        } catch {
            return nil
        }
    }

    // MARK: - Cleanup

    private func cleanupExport() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
            exportURL = nil
        }
        // After the share sheet dismisses, surface any photos that
        // couldn't be embedded during the build. Deferred this far so
        // the user isn't dealing with an alert stacked on top of the
        // share sheet — they see the happy-path share flow first, and
        // the "some photos were skipped" note is the last thing.
        if lastSkippedPhotoCount > 0 {
            let count = lastSkippedPhotoCount
            lastSkippedPhotoCount = 0
            alertTitle = "Some photos couldn't be included"
            alertMessage = "\(count) photo\(count == 1 ? "" : "s") couldn't be embedded in the export — the asset may have been deleted from your library or the resize step failed."
            showAlert = true
        }
    }

    private func describeError(_ error: PilgrimPackageError) -> String {
        switch error {
        case .noWalksFound:
            return "No walks found to export."
        case .encodingFailed:
            return "Failed to encode walk data."
        case .zipFailed:
            return "Failed to create archive."
        case .fileSystemError:
            return "A file system error occurred."
        case .invalidPackage:
            return "The file is not a valid .pilgrim package."
        case .decodingFailed:
            return "Failed to read walk data from the file."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported schema version: \(version). Please update the app."
        }
    }
}

// MARK: - Document Picker

struct PilgrimDocumentPicker: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let pilgrimType = UTType(filenameExtension: "pilgrim") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [pilgrimType])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
