import SwiftUI

struct DataCard: View {

    @ObservedObject private var tiles = PilgrimageTilesManager.shared
    @State private var waysDetail: String = ""
    @State private var mapsDetail: String = ""

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

            NavigationLink {
                OfflineMapsView()
            } label: {
                settingNavRow(label: "Maps", detail: mapsDetail)
            }
        }
        .settingsCard()
        .onAppear {
            // Counted the way the list counts: package stages are managed on
            // their route page, and a row that counted them said "5 ways"
            // above a list of one.
            let listed = WaysListModel.listable(WayStore.shared.list())
            waysDetail = WaysListModel.rowDetail(count: listed.count, bytes: WayStore.shared.diskUsage(of: listed))
            reloadMapsDetail()
        }
        // A card drawn before the store answered would say "none saved"
        // until Settings was left and reopened. Regions only: every step of
        // a save publishes too, and this reload decodes every stage Way of
        // the route off disk.
        .onReceive(tiles.regionsChanged) { _ in reloadMapsDetail() }
    }

    private func reloadMapsDetail() {
        mapsDetail = OfflineMapsModel.rowDetail(
            OfflineMapsModel.loadInstalled(packages: PilgrimagePackageManager.shared, tiles: tiles).saved)
    }
}
