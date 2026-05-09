import SwiftUI
import WebKit
import CoreStore
import Photos

/// Wraps a saved-file URL so it can be used as an `Identifiable` sheet item.
fileprivate struct PilgrimSaveItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct JourneyEditorView: View {

    @State private var isLoading = true
    @State private var walksJSON: String?
    @State private var error: String?
    @State private var savedFile: PilgrimSaveItem?

    var body: some View {
        ZStack {
            if let json = walksJSON {
                JourneyEditorWebView(
                    walksJSON: json,
                    isLoading: $isLoading,
                    savedFile: $savedFile
                )
                .ignoresSafeArea(edges: .bottom)
            }

            if isLoading {
                VStack(spacing: Constants.UI.Padding.normal) {
                    SwiftUI.ProgressView()
                        .tint(.stone)
                    Text(walksJSON == nil ? "Preparing your journey..." : "Opening editor...")
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

    private func prepareData() async {
        let systemString = UserPreferences.zodiacSystem.value
        let system: ZodiacSystem = systemString == "sidereal" ? .sidereal : .tropical
        let celestialEnabled = UserPreferences.celestialAwarenessEnabled.value

        do {
            let walks: [Walk] = try DataManager.dataStack.fetchAll(
                From<Walk>().orderBy(.ascending(\._startDate))
            )
            guard !walks.isEmpty else {
                error = "No walks yet. Take a walk first."
                isLoading = false
                return
            }

            let reliquaryEnabled = UserPreferences.walkReliquaryEnabled.value
                && PermissionManager.standard.isPhotosGranted

            var pilgrimWalks = walks.compactMap {
                PilgrimPackageConverter.convert(
                    walk: $0,
                    system: system,
                    celestialEnabled: celestialEnabled,
                    includePhotos: reliquaryEnabled
                )
            }

            if reliquaryEnabled {
                let snapshot = pilgrimWalks
                pilgrimWalks = await Task.detached(priority: .userInitiated) {
                    snapshot.map { Self.enrichWithInlinePhotos($0) }
                }.value
            }

            let encoder = PilgrimDateCoding.makeEncoder()
            let walksData = try encoder.encode(pilgrimWalks)

            let manifest = PilgrimPackageConverter.buildManifest(
                walkCount: pilgrimWalks.count,
                events: []
            )
            let manifestData = try encoder.encode(manifest)

            guard let walksString = String(data: walksData, encoding: .utf8),
                  let manifestString = String(data: manifestData, encoding: .utf8) else {
                error = "Failed to encode walk data."
                isLoading = false
                return
            }

            let json = "{\"walks\":\(walksString),\"manifest\":\(manifestString)}"
            await MainActor.run { walksJSON = json }
        } catch {
            self.error = "Failed to load walks."
            isLoading = false
        }
    }

    private static func enrichWithInlinePhotos(_ walk: PilgrimWalk) -> PilgrimWalk {
        guard let photos = walk.photos, !photos.isEmpty else { return walk }

        var enriched = walk
        enriched.photos = photos.compactMap { photo in
            guard let dataUrl = loadPhotoDataUrl(localIdentifier: photo.localIdentifier) else {
                return nil
            }
            return PilgrimPhoto(
                localIdentifier: photo.localIdentifier,
                capturedAt: photo.capturedAt,
                capturedLat: photo.capturedLat,
                capturedLng: photo.capturedLng,
                keptAt: photo.keptAt,
                embeddedPhotoFilename: photo.embeddedPhotoFilename,
                inlineUrl: dataUrl
            )
        }
        return enriched
    }

    private static func loadPhotoDataUrl(localIdentifier: String) -> String? {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .exact

        let targetSize = CGSize(width: 600, height: 600)

        var result: String?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image,
                  let jpegData = image.jpegData(compressionQuality: 0.7) else { return }
            result = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        }
        return result
    }
}

/// JS shim injected into the editor page. Intercepts `<a download>` clicks
/// targeting `blob:` URLs by reading the blob via fetch() and forwarding
/// the bytes to iOS through the `savePilgrim` message handler. Returns
/// early from the original click() to suppress WKWebView's native
/// download path (which fails with "DownloadFailed" because blob URLs
/// have no Content-Disposition header for the system download manager).
///
/// We override `HTMLAnchorElement.prototype.click` AND wrap
/// `dispatchEvent` for click events on download anchors, because some
/// bundlers compile `a.click()` down to dispatchEvent under the hood.
private let savePilgrimShimJS: String = """
(function() {
  if (window.__pilgrimSaveShimInstalled) return;
  window.__pilgrimSaveShimInstalled = true;

  function captureBlobAndSend(anchor) {
    fetch(anchor.href)
      .then(function(r) { return r.blob(); })
      .then(function(blob) {
        return blob.arrayBuffer().then(function(buf) {
          const bytes = new Uint8Array(buf);
          let binary = '';
          const chunk = 0x8000;
          for (let i = 0; i < bytes.length; i += chunk) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
          }
          const base64 = btoa(binary);
          window.webkit.messageHandlers.savePilgrim.postMessage({
            filename: anchor.download || 'walk.pilgrim',
            base64: base64,
            mime: blob.type || 'application/octet-stream'
          });
        });
      })
      .catch(function(err) {
        console.error('[savePilgrimShim] capture failed:', err);
      });
  }

  function isDownloadAnchor(target) {
    return target instanceof HTMLAnchorElement
      && target.download
      && typeof target.href === 'string'
      && target.href.indexOf('blob:') === 0;
  }

  // Capture-phase listener catches the click before WebKit's native
  // download handling kicks in. Calling preventDefault + stopPropagation
  // suppresses the native download attempt.
  document.addEventListener('click', function(ev) {
    const target = ev.target.closest ? ev.target.closest('a[download]') : null;
    if (target && isDownloadAnchor(target)) {
      ev.preventDefault();
      ev.stopPropagation();
      ev.stopImmediatePropagation();
      captureBlobAndSend(target);
    }
  }, true);

  // Belt-and-suspenders: also override the prototype click() for any
  // bundled code path that bypasses dispatchEvent entirely.
  const origClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function() {
    try {
      if (isDownloadAnchor(this)) {
        captureBlobAndSend(this);
        return;
      }
    } catch (err) {
      console.error('[savePilgrimShim] prototype click intercept threw:', err);
    }
    return origClick.apply(this, arguments);
  };
})();
"""

fileprivate struct JourneyEditorWebView: UIViewRepresentable {

    let walksJSON: String
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
        let shim = WKUserScript(
            source: savePilgrimShimJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContent.addUserScript(shim)
        userContent.add(context.coordinator, name: "savePilgrim")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

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
        Coordinator(walksJSON: walksJSON, isLoading: $isLoading, savedFile: $savedFile)
    }

    fileprivate class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {

        // Stores the destination URL we hand WKDownload so we can present
        // it once the download finishes.
        private var pendingDownloadDestination: URL?
        let walksJSON: String
        @Binding var isLoading: Bool
        @Binding var savedFile: PilgrimSaveItem?
        private var injected = false

        fileprivate init(
            walksJSON: String,
            isLoading: Binding<Bool>,
            savedFile: Binding<PilgrimSaveItem?>
        ) {
            self.walksJSON = walksJSON
            self._isLoading = isLoading
            self._savedFile = savedFile
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !injected else { return }
            injected = true

            let jsonObj = jsonObject()
            Task { @MainActor in
                do {
                    try await waitForBridgeReady(in: webView)
                    // edit.pilgrimapp.org runs the same JS bundle as
                    // view.pilgrimapp.org with edit features enabled —
                    // the bridge API is `window.pilgrimViewer`, NOT
                    // `pilgrimEditor`. There is no separate editor
                    // global.
                    _ = try await webView.callAsyncJavaScript(
                        "window.pilgrimViewer.loadData(data)",
                        arguments: ["data": jsonObj],
                        contentWorld: .page
                    )
                } catch {
                    print("[JourneyEditor] JS injection failed: \(error)")
                }
                isLoading = false
            }
        }

        /// Polls `window.pilgrimViewer` until it's defined, up to ~5s.
        /// Replaces a fixed 1.0s sleep that silently failed when the JS
        /// bundle took longer to initialize.
        @MainActor
        private func waitForBridgeReady(in webView: WKWebView) async throws {
            let pollMs: UInt64 = 100
            let maxAttempts = 50  // 50 × 100ms = 5s
            for _ in 0..<maxAttempts {
                if let ready = try? await webView.callAsyncJavaScript(
                    "return typeof window.pilgrimViewer === 'object' && typeof window.pilgrimViewer.loadData === 'function'",
                    arguments: [:],
                    contentWorld: .page
                ) as? Bool, ready {
                    return
                }
                try await Task.sleep(nanoseconds: pollMs * 1_000_000)
            }
            print("[JourneyEditor] window.pilgrimViewer not ready after 5s — bridge missing or page failed")
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
            if let url = navigationAction.request.url, url.scheme == "blob" {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
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
            guard message.name == "savePilgrim",
                  let payload = message.body as? [String: Any],
                  let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64) else {
                print("[JourneyEditor] savePilgrim message malformed")
                return
            }

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

        private func jsonObject() -> Any {
            guard let data = walksJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                return [:]
            }
            return obj
        }
    }
}
