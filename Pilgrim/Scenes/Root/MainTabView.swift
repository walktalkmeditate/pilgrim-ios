import SwiftUI

enum MainTab {
    case path, journal, settings
}

struct MainTabView: View {

    @State private var selectedTab: MainTab = .path
    @State private var sealShareURL: URL?
    @StateObject private var coordinator = MainCoordinator()
    @EnvironmentObject private var appearanceManager: AppearanceManager

    var body: some View {
        // Touch themeID so the body re-evaluates on appearance flip and
        // .tint(.stone) below recomputes to the new mode's accent color.
        // selectedTab + coordinator @State survive a body re-eval (only
        // identity change resets @State).
        _ = appearanceManager.themeID
        return TabView(selection: $selectedTab) {
            Tab("Path", systemImage: "figure.walk", value: .path) {
                WalkStartView(onStartWalk: { mode in
                    coordinator.startWalk(mode: mode)
                })
            }
            .accessibilityIdentifier("tab_path")

            Tab("Journal", systemImage: "book", value: .journal) {
                MainCoordinatorView(coordinator: coordinator)
            }
            .accessibilityIdentifier("tab_journal")

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
            .accessibilityIdentifier("tab_settings")
        }
        .tint(.stone)
        .fullScreenCover(item: $coordinator.activeWalkViewModel, onDismiss: {
            coordinator.handleActiveWalkDismiss()
        }) { vm in
            ActiveWalkView(viewModel: vm, onCancel: { coordinator.cancelWalk() })
                .constellationDecorated(nebulae: false)
        }
        .sheet(item: $coordinator.completedSnapshot, onDismiss: {
            coordinator.handleSummaryDismiss()
        }) { snapshot in
            WalkSummaryView(walk: snapshot)
                .constellationDecorated(nebulae: false)
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
        .overlay {
            if coordinator.showSealReveal, let walk = coordinator.sealRevealWalk {
                SealRevealView(
                    walk: walk,
                    onDismiss: {
                        coordinator.handleSealRevealDismiss()
                    },
                    onShareSeal: { image in
                        let url = WalkSharingButtons.writeToTemp(image: image, name: "pilgrim-seal-\(walk.uuid?.uuidString.prefix(8) ?? "share")")
                        coordinator.handleSealRevealDismiss()
                        sealShareURL = url
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.showSealReveal)
        .sheet(item: $sealShareURL) { url in
            ShareSheet(items: [url])
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
