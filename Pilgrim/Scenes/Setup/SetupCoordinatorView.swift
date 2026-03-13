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
                WelcomeView(viewModel: WelcomeViewModel {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        phase = .permissions
                    }
                })
                .transition(.opacity)

            case .permissions:
                PermissionsView(viewModel: PermissionsViewModel(
                    permissionManager: PermissionManager.standard,
                    onComplete: {
                        withAnimation(.easeInOut(duration: Constants.UI.Motion.appear)) {
                            phase = .breathTransition
                        }
                    }
                ))
                .transition(.opacity)

            case .breathTransition:
                BreathTransitionView {
                    UserPreferences.isSetUp.value = true
                }
                .transition(.opacity)
            }
        }
    }
}
