import SwiftUI

struct RootCoordinatorView: View {

    @EnvironmentObject var appDelegate: AppDelegate
    @ObservedObject var viewModel: RootCoordinatorViewModel

    var body: some View {
        switch appDelegate.appLaunchState {
        case .loading:
            LaunchLoadingView()
        case .migration:
            SwiftUI.ProgressView("Migrating data...")
        case .done:
            switch viewModel.rootState {
            case .setup:
                SetupCoordinatorView()
            case .main:
                MainTabView()
            }
        }
    }
}
