import SwiftUI

struct DataCard: View {

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Data", subtitle: "Your walk archive")

            NavigationLink {
                DataSettingsView()
            } label: {
                settingNavRow(label: "Export & Import")
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
}
