import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(named: "stone")
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
