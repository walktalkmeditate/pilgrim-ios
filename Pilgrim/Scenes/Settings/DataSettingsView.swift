import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct DataSettingsView: View {

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isExportingRecordings = false
    @State private var showDocumentPicker = false
    @State private var showJourneyViewer = false
    @State private var exportURL: URL?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var recordingCount = 0

    private var isBusy: Bool { isExporting || isImporting || isExportingRecordings }

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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("View My Journey")
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Text("See all your walks rendered in your browser. Your data stays on your device.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
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

    private func exportData() {
        isExporting = true
        PilgrimPackageBuilder.build { result in
            isExporting = false
            switch result {
            case .success(let url):
                exportURL = url
            case .failure(let error):
                alertTitle = "Export Failed"
                alertMessage = describeError(error)
                showAlert = true
            }
        }
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
