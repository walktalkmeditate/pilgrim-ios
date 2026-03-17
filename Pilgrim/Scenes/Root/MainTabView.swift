import SwiftUI

enum MainTab {
    case path, journal, settings
}

struct MainTabView: View {

    @State private var selectedTab: MainTab = .path
    @StateObject private var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Path", systemImage: "figure.walk", value: .path) {
                WalkStartView(onStartWalk: { mode in
                    coordinator.startWalk(mode: mode)
                })
            }

            Tab("Journal", systemImage: "book", value: .journal) {
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
        .alert("Location Required", isPresented: $coordinator.showLocationDenied) {
            Button("Settings", action: coordinator.openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pilgrim needs location access to track your route. Please enable it in Settings.")
        }
        .overlay(alignment: .top) {
            if let date = coordinator.recoveredWalkDate {
                RecoveryBanner(date: date)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: coordinator.recoveredWalkDate != nil)
    }
}
