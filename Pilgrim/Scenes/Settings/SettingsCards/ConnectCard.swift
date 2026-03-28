import SwiftUI

struct ConnectCard: View {

    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6760921056")!
    private let reviewURL = URL(string: "https://apps.apple.com/app/id6760921056?action=write-review")!

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Connect", subtitle: "Share the path")

            Button {
                share()
            } label: {
                connectRow(icon: "square.and.arrow.up", label: "Share Pilgrim")
            }

            Button {
                UIApplication.shared.open(reviewURL)
            } label: {
                connectRow(icon: "heart", label: "Rate Pilgrim", external: true)
            }

            NavigationLink {
                FeedbackView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    settingNavRow(label: "Leave a Trail Note")
                    Text("Share a thought, report a bug, or suggest a feature")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
        }
        .settingsCard()
    }

    private func connectRow(icon: String, label: String, external: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 24, alignment: .center)
                .foregroundColor(.stone)
            Text(label)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            Spacer()
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    private func share() {
        let text = "I've been walking with Pilgrim — it tracks your walks, records voice notes, and even has a meditation mode. No accounts, no tracking, everything stays on your phone. Free and open source."
        let activityVC = UIActivityViewController(activityItems: [text, appStoreURL], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            var presenter = root
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            activityVC.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activityVC, animated: true)
        }
    }
}
