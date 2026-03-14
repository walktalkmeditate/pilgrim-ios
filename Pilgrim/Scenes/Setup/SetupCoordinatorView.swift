import SwiftUI

struct SetupCoordinatorView: View {

    enum Phase {
        case threshold
        case permissions
        case breathTransition
    }

    @State private var phase: Phase = .threshold

    var body: some View {
        ZStack {
            switch phase {
            case .threshold:
                ThresholdPhaseView {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        phase = .permissions
                    }
                }
                .transition(.opacity)

            case .permissions:
                PermissionsPhaseView {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                        phase = .breathTransition
                    }
                }
                .transition(.opacity)

            case .breathTransition:
                BreathTransitionView {
                    UserPreferences.startWalkOnFirstLaunch.value = true
                    UserPreferences.isSetUp.value = true
                }
                .transition(.opacity)
            }
        }
    }
}

private struct ThresholdPhaseView: View {
    @StateObject private var viewModel: WelcomeViewModel

    init(onBegin: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: WelcomeViewModel(beginAction: onBegin))
    }

    var body: some View {
        WelcomeView(viewModel: viewModel)
    }
}

private struct PermissionsPhaseView: View {
    @StateObject private var viewModel: PermissionsViewModel

    init(onComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: PermissionsViewModel(
            permissionManager: PermissionManager.standard,
            onComplete: onComplete
        ))
    }

    var body: some View {
        PermissionsView(viewModel: viewModel)
    }
}
