import SwiftUI
import WebKit
import CoreStore
import Photos

/// Wraps a saved-file URL so it can be used as an `Identifiable` sheet item.
fileprivate struct PilgrimSaveItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Pre-built `.pilgrim` zip payload for the editor. The editor's save flow
/// requires the original ZIP buffer (so it can apply mods on top of the
/// existing archive structure rather than reconstructing from scratch),
/// so we ship the actual zip bytes via the `pilgrimViewer.loadFile`
/// bridge — `loadData` only sets walks/manifest and the editor would bail
/// at save time with `originalPilgrimBuffer` undefined.
fileprivate struct PilgrimPayload {
    let filename: String
    let base64: String
}

struct JourneyEditorView: View {

    @State private var isLoading = true
    @State private var pilgrimPayload: PilgrimPayload?
    @State private var error: String?
    @State private var savedFile: PilgrimSaveItem?

    var body: some View {
        ZStack {
            if let payload = pilgrimPayload {
                JourneyEditorWebView(
                    payload: payload,
                    isLoading: $isLoading,
                    savedFile: $savedFile
                )
                .ignoresSafeArea(edges: .bottom)
            }

            if isLoading {
                VStack(spacing: Constants.UI.Padding.normal) {
                    SwiftUI.ProgressView()
                        .tint(.stone)
                    Text(pilgrimPayload == nil ? "Preparing your journey..." : "Opening editor...")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }

            if let error {
                VStack(spacing: Constants.UI.Padding.normal) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.fog)
                    Text(error)
                        .font(Constants.Typography.body)
                        .foregroundColor(.stone)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Edit My Journey")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(item: $savedFile, onDismiss: {
            // The Share Sheet has been closed (whether the user saved or
            // cancelled). Clean up the temp file — the share sheet has
            // already either copied the bytes to the user's chosen
            // destination or the user has decided not to keep them.
            if let url = savedFile?.url {
                try? FileManager.default.removeItem(at: url)
            }
        }) { item in
            ShareSheet(items: [item.url])
        }
        .task { await prepareData() }
    }

    /// Build the actual `.pilgrim` ZIP via `PilgrimPackageBuilder` (the
    /// same code path used for export). The editor's save flow needs the
    /// original ZIP bytes loaded into `originalPilgrimBuffer` — sending
    /// only walks JSON via `pilgrimViewer.loadData` leaves that slot
    /// undefined and save bails silently.
    private func prepareData() async {
        let walkCount: Int
        do {
            walkCount = try DataManager.dataStack.fetchCount(From<Walk>())
        } catch {
            self.error = "Failed to load walks."
            isLoading = false
            return
        }
        guard walkCount > 0 else {
            error = "No walks yet. Take a walk first."
            isLoading = false
            return
        }

        let reliquaryEnabled = UserPreferences.walkReliquaryEnabled.value
            && PermissionManager.standard.isPhotosGranted

        let payload: PilgrimPayload
        do {
            payload = try await Self.buildPayload(includePhotos: reliquaryEnabled)
        } catch let buildError as PilgrimPackageError {
            print("[JourneyEditor] PilgrimPackageBuilder failed: \(buildError)")
            self.error = "Failed to package walks for editing."
            isLoading = false
            return
        } catch {
            print("[JourneyEditor] PilgrimPackageBuilder failed: \(error)")
            self.error = "Failed to package walks for editing."
            isLoading = false
            return
        }

        await MainActor.run { pilgrimPayload = payload }
    }

    /// Bridges `PilgrimPackageBuilder.build`'s completion-handler API to
    /// async-await, reads the resulting `.pilgrim` file off the main
    /// actor, base64-encodes it, then deletes the temp file.
    private static func buildPayload(includePhotos: Bool) async throws -> PilgrimPayload {
        let result: PilgrimPackageBuildResult = try await withCheckedThrowingContinuation { cont in
            PilgrimPackageBuilder.build(includePhotos: includePhotos) { result in
                switch result {
                case .success(let value):
                    cont.resume(returning: value)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: result.url) }
            let data = try Data(contentsOf: result.url)
            let base64 = data.base64EncodedString()
            let filename = result.url.lastPathComponent
            return PilgrimPayload(filename: filename, base64: base64)
        }.value
    }
}

fileprivate struct JourneyEditorWebView: UIViewRepresentable {

    let payload: PilgrimPayload
    @Binding var isLoading: Bool
    @Binding var savedFile: PilgrimSaveItem?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Use a non-persistent data store so the editor's JS chunks
        // aren't served from a stale WKWebView URL cache. Without this,
        // Safari/WebKit can hand back the prior version of the bundle
        // even after a fresh deploy at edit.pilgrimapp.org — and the
        // prior version doesn't know about the savePilgrim host bridge,
        // which is exactly the failure the user was seeing.
        config.websiteDataStore = .nonPersistent()

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "savePilgrim")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Allow Safari Web Inspector to attach in Debug builds. iOS 16.4+
        // requires this explicit opt-in even for development builds; without
        // it WKWebViews show as "No Inspectable Applications" in Safari's
        // Develop menu.
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // Force-reload from the network on every entry. We can't rely on
        // the WKWebView's HTTP cache to invalidate when the editor
        // deploys a new bundle.
        var request = URLRequest(url: Config.Web.editor)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(payload: payload, isLoading: $isLoading, savedFile: $savedFile)
    }

    fileprivate class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {

        // Stores the destination URL we hand WKDownload so we can present
        // it once the download finishes.
        private var pendingDownloadDestination: URL?
        let payload: PilgrimPayload
        @Binding var isLoading: Bool
        @Binding var savedFile: PilgrimSaveItem?
        private var injected = false

        fileprivate init(
            payload: PilgrimPayload,
            isLoading: Binding<Bool>,
            savedFile: Binding<PilgrimSaveItem?>
        ) {
            self.payload = payload
            self._isLoading = isLoading
            self._savedFile = savedFile
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !injected else { return }
            injected = true

            Task { @MainActor in
                do {
                    try await waitForBridgeReady(in: webView)
                    // Use loadFile (added in pilgrim-viewer v1.4.5) so the
                    // editor's save flow has the original .pilgrim ZIP
                    // buffer. loadData alone leaves originalPilgrimBuffer
                    // undefined and save bails silently.
                    _ = try await webView.callAsyncJavaScript(
                        "await window.pilgrimViewer.loadFile(filename, base64); return true;",
                        arguments: [
                            "filename": payload.filename,
                            "base64": payload.base64
                        ],
                        contentWorld: .page
                    )
                    print("[JourneyEditor] loadFile injected, \(payload.base64.count) base64 chars")
                } catch {
                    print("[JourneyEditor] JS injection failed: \(error)")
                }
                isLoading = false
            }
        }

        /// Polls `window.pilgrimViewer.loadFile` until it's defined, up to
        /// ~5s. Replaces a fixed sleep that silently failed when the JS
        /// bundle took longer to initialize.
        @MainActor
        private func waitForBridgeReady(in webView: WKWebView) async throws {
            let pollMs: UInt64 = 100
            let maxAttempts = 50  // 50 × 100ms = 5s
            for _ in 0..<maxAttempts {
                if let ready = try? await webView.callAsyncJavaScript(
                    "return typeof window.pilgrimViewer === 'object' && typeof window.pilgrimViewer.loadFile === 'function'",
                    arguments: [:],
                    contentWorld: .page
                ) as? Bool, ready {
                    return
                }
                try await Task.sleep(nanoseconds: pollMs * 1_000_000)
            }
            print("[JourneyEditor] window.pilgrimViewer.loadFile not ready after 5s — bridge missing or page failed")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[JourneyEditor] Page load failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[JourneyEditor] Navigation failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
        }

        // MARK: - WKDownloadDelegate (backup for any save path the JS shim misses)

        /// Catches blob: URL navigations that escape the JS-shim layer
        /// (e.g. WebKit's native download path triggered by a bundled
        /// `<a download>` click that didn't go through prototype.click).
        /// Routes to .download so we can capture the bytes via WKDownload.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url?.absoluteString ?? "<no url>"
            if let scheme = navigationAction.request.url?.scheme, scheme == "blob" {
                print("[JourneyEditor] decidePolicyFor blob URL → .download (\(url.prefix(80)))")
                decisionHandler(.download)
                return
            }
            print("[JourneyEditor] decidePolicyFor → .allow (\(url.prefix(80)))")
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            print("[JourneyEditor] navigationAction didBecome WKDownload")
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            // The blob URL won't have a useful suggestedFilename. Use the
            // download attribute if exposed; otherwise fall back to
            // walk.pilgrim. Write into NSTemporaryDirectory so the Share
            // Sheet can read it.
            let name: String
            if !suggestedFilename.isEmpty, suggestedFilename != "Unknown" {
                name = suggestedFilename
            } else {
                name = "walk.pilgrim"
            }
            let safeName = name.replacingOccurrences(of: "/", with: "_")
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: dest)
            pendingDownloadDestination = dest
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let dest = pendingDownloadDestination else { return }
            pendingDownloadDestination = nil
            DispatchQueue.main.async { [weak self] in
                self?.savedFile = PilgrimSaveItem(url: dest)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            print("[JourneyEditor] WKDownload failed: \(error)")
            pendingDownloadDestination = nil
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "pilgrimDebug" {
                if let s = message.body as? String {
                    print("[PilgrimWeb] \(s)")
                }
                return
            }

            print("[JourneyEditor] message arrived: \(message.name)")
            guard message.name == "savePilgrim",
                  let payload = message.body as? [String: Any],
                  let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64) else {
                print("[JourneyEditor] savePilgrim message malformed: \(message.body)")
                return
            }
            print("[JourneyEditor] savePilgrim received \(data.count) bytes")

            let filename = (payload["filename"] as? String) ?? "walk.pilgrim"
            let safeName = filename.replacingOccurrences(of: "/", with: "_")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(safeName)

            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try data.write(to: tempURL, options: .atomic)
                DispatchQueue.main.async { [weak self] in
                    self?.savedFile = PilgrimSaveItem(url: tempURL)
                }
            } catch {
                print("[JourneyEditor] could not write saved .pilgrim: \(error)")
            }
        }

    }
}
