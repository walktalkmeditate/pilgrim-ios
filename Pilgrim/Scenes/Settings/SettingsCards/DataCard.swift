import SwiftUI

struct DataCard: View {

    @State private var waysDetail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Data", subtitle: "Your walk archive")

            NavigationLink {
                DataSettingsView()
            } label: {
                settingNavRow(label: "Export & Import")
            }

            NavigationLink {
                WaysListView()
            } label: {
                settingNavRow(label: "Ways", detail: waysDetail)
            }
        }
        .settingsCard()
        .onAppear {
            let count = WayStore.shared.list().count
            let mb = Double(WayStore.shared.totalDiskUsage()) / 1_000_000
            waysDetail = "\(count) ways · \(String(format: "%.1f MB", mb))"
        }
    }
}
