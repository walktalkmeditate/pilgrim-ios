import Foundation
import WebKit
import Combine

final class WebViewLoader: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var loadState: LoadState = .loading

    let webView: WKWebView
    let initialURL: URL

    private let navigationDelegate: NavigationDelegate

    init(url: URL) {
        self.initialURL = url

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.isOpaque = false
        self.webView.backgroundColor = .clear
        self.webView.scrollView.backgroundColor = .clear

        self.navigationDelegate = NavigationDelegate()
        self.webView.navigationDelegate = self.navigationDelegate
        self.navigationDelegate.loader = self

        self.webView.load(URLRequest(url: url))
    }

    deinit {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func retry() {
        loadState = .loading
        webView.load(URLRequest(url: initialURL))
    }

    func handleDidFinish() {
        loadState = .loaded
    }

    func handleDidFail() {
        loadState = .failed
    }

    func shouldAllowNavigation(to url: URL) -> Bool {
        return url == initialURL
    }
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {

    weak var loader: WebViewLoader?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let loader = loader else {
            decisionHandler(.cancel)
            return
        }

        if loader.shouldAllowNavigation(to: url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loader?.handleDidFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loader?.handleDidFail()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loader?.handleDidFail()
    }
}
