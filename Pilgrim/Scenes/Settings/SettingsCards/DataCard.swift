import SwiftUI
#if DEBUG
import MapboxMaps
#endif

struct DataCard: View {

    @ObservedObject private var tiles = PilgrimageTilesManager.shared
    @State private var waysDetail: String = ""
    @State private var mapsDetail: String = ""
    #if DEBUG
    @State private var simulateOffline = false
    #endif

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

            #if DEBUG
            // Forces the Mapbox stack offline without airplane mode, so a
            // saved stage can be opened and seen to render — or not — at
            // home. Process-wide: it is reset on launch and never persisted.
            settingToggle(label: "simulate no signal for maps",
                          description: "DEBUG · the map stops fetching until this is off",
                          isOn: $simulateOffline) { on in
                OfflineSwitch.shared.isMapboxStackConnected = !on
            }
            #endif
        }
        .settingsCard()
        .onAppear {
            // Counted the way the list counts: package stages are managed on
            // their route page, and a row that counted them said "5 ways"
            // above a list of one.
            let listed = WaysListModel.listable(WayStore.shared.list())
            waysDetail = WaysListModel.rowDetail(count: listed.count, bytes: WayStore.shared.diskUsage(of: listed))
            reloadMapsDetail()
            #if DEBUG
            simulateOffline = !OfflineSwitch.shared.isMapboxStackConnected
            #endif
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
