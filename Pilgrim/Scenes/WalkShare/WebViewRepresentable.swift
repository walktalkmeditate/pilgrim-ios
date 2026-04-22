import SwiftUI
import WebKit

struct WebViewRepresentable: UIViewRepresentable {

    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // WebView state is managed by WebViewLoader; nothing to update here.
    }
}
