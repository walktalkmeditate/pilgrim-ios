import SwiftUI

enum MainTab {
    case log, settings
}

struct MainTabView: View {

    @State private var selectedTab: MainTab = .log

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Log", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", value: .log) {
                MainCoordinatorView()
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tint(.stone)
    }
}
