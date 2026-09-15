import SwiftUI
#if DEBUG
import MapboxMaps
#endif

struct DataCard: View {

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
            let count = WayStore.shared.list().count
            let mb = Double(WayStore.shared.totalDiskUsage()) / 1_000_000
            waysDetail = "\(count) ways · \(String(format: "%.1f MB", mb))"
            mapsDetail = OfflineMapsModel.rowDetail(
                OfflineMapsModel.loadInstalled(packages: PilgrimagePackageManager.shared, tiles: PilgrimageTilesManager.shared).saved)
            #if DEBUG
            simulateOffline = !OfflineSwitch.shared.isMapboxStackConnected
            #endif
        }
    }
}
