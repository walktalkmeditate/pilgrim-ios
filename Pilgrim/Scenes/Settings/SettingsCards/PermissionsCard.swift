import SwiftUI

struct PermissionsCard: View {

    @ObservedObject var permissionVM: PermissionStatusViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Permissions", subtitle: "What Pilgrim can access")

            permissionRow(
                title: "Location",
                subtitle: "Track your route",
                state: permissionVM.locationState,
                onGrant: permissionVM.requestLocation
            )

            permissionRow(
                title: "Microphone",
                subtitle: "Record reflections",
                state: permissionVM.microphoneState,
                onGrant: permissionVM.requestMicrophone
            )

            permissionRow(
                title: "Motion",
                subtitle: "Count your steps",
                state: permissionVM.motionState,
                onGrant: permissionVM.requestMotion
            )
        }
        .settingsCard()
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            permissionVM.refresh()
        }
    }

    // MARK: - Permission Row

    private func permissionRow(
        title: String,
        subtitle: String,
        state: PermissionState,
        onGrant: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            Circle()
                .fill(dotColor(for: state))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(subtitle)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            Spacer()

            permissionAction(state: state, onGrant: onGrant)
        }
    }

    private func dotColor(for state: PermissionState) -> Color {
        switch state {
        case .granted: return .moss
        case .notDetermined: return .dawn
        case .denied: return .rust
        case .restricted: return .fog
        }
    }

    @ViewBuilder
    private func permissionAction(state: PermissionState, onGrant: @escaping () -> Void) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark")
                .foregroundColor(.moss)
                .font(Constants.Typography.caption)
        case .notDetermined:
            Button("Grant", action: onGrant)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        case .denied:
            Button("Settings", action: permissionVM.openSettings)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        case .restricted:
            Text("Restricted")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }
}
