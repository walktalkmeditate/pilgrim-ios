import SwiftUI

class MainCoordinator: ObservableObject {

    let homeViewModel = HomeViewModel()
    @Published var activeWalkViewModel: ActiveWalkViewModel?
    @Published var completedSnapshot: TempWalk?
    @Published var showSaveError = false

    private var pendingSnapshot: TempWalk?
    private var callbacksConfigured = false

    func setupCallbacks() {
        guard !callbacksConfigured else { return }
        callbacksConfigured = true

        homeViewModel.onStartWalk = { [weak self] in
            self?.startWalk()
        }
    }

    func startWalk() {
        guard activeWalkViewModel == nil else { return }
        let vm = ActiveWalkViewModel()
        vm.onWalkCompleted = { [weak self] snapshot in
            DataManager.saveWalk(object: snapshot) { success, error, walk in
                guard let self else { return }
                if success {
                    self.pendingSnapshot = snapshot
                    self.activeWalkViewModel = nil
                } else {
                    self.showSaveError = true
                }
            }
        }
        activeWalkViewModel = vm
    }

    func checkFirstLaunchWalk() {
        guard UserPreferences.startWalkOnFirstLaunch.value else { return }
        UserPreferences.startWalkOnFirstLaunch.value = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startWalk()
        }
    }

    func handleActiveWalkDismiss() {
        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            completedSnapshot = snapshot
        }
    }

    func handleSummaryDismiss() {
        homeViewModel.loadWalks()
    }
}

struct MainCoordinatorView: View {

    @StateObject private var coordinator = MainCoordinator()

    var body: some View {
        HomeView(viewModel: coordinator.homeViewModel)
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
            .onAppear {
                coordinator.setupCallbacks()
                coordinator.checkFirstLaunchWalk()
            }
    }
}
