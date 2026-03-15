import SwiftUI

class MainCoordinator: ObservableObject {

    let homeViewModel = HomeViewModel()
    @Published var activeWalkViewModel: ActiveWalkViewModel?
    @Published var completedSnapshot: TempWalk?
    @Published var showSaveError = false

    private var pendingSnapshot: TempWalk?

    func startWalk(mode: WalkMode = .solo) {
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

    @ObservedObject var coordinator: MainCoordinator

    var body: some View {
        HomeView(viewModel: coordinator.homeViewModel)
    }
}
