import SwiftUI

struct HomePlaceholderView: View {

    let onStartWalk: () -> Void

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
                HomePlaceholderThresholdView {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        phase = .permissions
                    }
                }
                .transition(.opacity)

            case .permissions:
                HomePlaceholderPermissionsView {
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.breath)) {
                        phase = .breathTransition
                    }
                }
                .transition(.opacity)

            case .breathTransition:
                BreathTransitionView {
                    onStartWalk()
                    withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                        phase = .threshold
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct HomePlaceholderThresholdView: View {
    @StateObject private var viewModel: WelcomeViewModel

    init(onBegin: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: WelcomeViewModel(beginAction: onBegin))
    }

    var body: some View {
        WelcomeView(viewModel: viewModel)
    }
}

private struct HomePlaceholderPermissionsView: View {
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
