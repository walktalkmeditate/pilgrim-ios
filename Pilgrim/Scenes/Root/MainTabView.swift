import SwiftUI

enum MainTab {
    case home, log, settings
}

struct MainTabView: View {

    @State private var selectedTab: MainTab = .home
    @StateObject private var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomePlaceholderView(onStartWalk: {
                    coordinator.startWalk()
                })
            }

            Tab("Log", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", value: .log) {
                MainCoordinatorView(coordinator: coordinator)
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tint(.stone)
        .fullScreenCover(item: $coordinator.activeWalkViewModel, onDismiss: {
            coordinator.handleActiveWalkDismiss()
        }) { vm in
            ActiveWalkView(viewModel: vm)
        }
        .sheet(item: $coordinator.completedSnapshot, onDismiss: {
            coordinator.handleSummaryDismiss()
        }) { snapshot in
            WalkSummaryView(walk: snapshot)
        }
        .alert("Save Failed", isPresented: $coordinator.showSaveError) {
            Button("Dismiss") {
                coordinator.activeWalkViewModel = nil
            }
        } message: {
            Text("Your walk could not be saved. Please try again.")
        }
    }
}
