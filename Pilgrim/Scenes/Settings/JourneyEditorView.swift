import SwiftUI
import WebKit
import CoreStore
import Photos

struct JourneyEditorView: View {

    @State private var isLoading = true
    @State private var walksJSON: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            if let json = walksJSON {
                JourneyEditorWebView(walksJSON: json, isLoading: $isLoading)
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
        .background(Color.parchment)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Edit My Journey")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
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
                pilgrimWalks = pilgrimWalks.map { Self.enrichWithInlinePhotos($0) }
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

struct JourneyEditorWebView: UIViewRepresentable {

    let walksJSON: String
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: Config.Web.editor))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(walksJSON: walksJSON, isLoading: $isLoading)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let walksJSON: String
        @Binding var isLoading: Bool
        private var injected = false

        init(walksJSON: String, isLoading: Binding<Bool>) {
            self.walksJSON = walksJSON
            self._isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !injected else { return }
            injected = true

            let jsonObj = jsonObject()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                Task { @MainActor in
                    do {
                        _ = try await webView.callAsyncJavaScript(
                            "window.pilgrimEditor.loadData(data)",
                            arguments: ["data": jsonObj],
                            contentWorld: .page
                        )
                    } catch {
                        print("[JourneyEditor] JS injection failed: \(error)")
                    }
                    self?.isLoading = false
                }
            }
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

        private func jsonObject() -> Any {
            guard let data = walksJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else {
                return [:]
            }
            return obj
        }
    }
}
