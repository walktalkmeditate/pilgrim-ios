import SwiftUI

struct GeneralSettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()
    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers

    var body: some View {
        List {
            unitsSection
            permissionsSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("General")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear { permissionVM.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            permissionVM.refresh()
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Units")
                        .font(Constants.Typography.body)
                    Spacer()
                    Picker("", selection: $isMetric) {
                        Text("Metric").tag(true)
                        Text("Imperial").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: isMetric) { _, metric in
                        applyUnitSystem(metric: metric)
                    }
                }
                Text(isMetric ? "km · min/km · m" : "mi · min/mi · ft")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        } header: {
            Text("Units")
                .font(Constants.Typography.caption)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            permissionRow(
                icon: "location.fill",
                title: "Location",
                subtitle: "Track your route",
                state: permissionVM.locationState,
                onGrant: permissionVM.requestLocation
            )
            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                subtitle: "Record reflections",
                state: permissionVM.microphoneState,
                onGrant: permissionVM.requestMicrophone
            )
            permissionRow(
                icon: "figure.walk",
                title: "Motion",
                subtitle: "Count your steps",
                state: permissionVM.motionState,
                onGrant: permissionVM.requestMotion
            )
        } header: {
            Text("Permissions")
                .font(Constants.Typography.caption)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        state: PermissionState,
        onGrant: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.stone)
                .frame(width: 24)

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

    // MARK: - Unit System

    private func applyUnitSystem(metric: Bool) {
        if metric {
            UserPreferences.distanceMeasurementType.value = .kilometers
            UserPreferences.altitudeMeasurementType.value = .meters
            UserPreferences.speedMeasurementType.value = .minutesPerLengthUnit(from: .kilometers)
            UserPreferences.weightMeasurementType.value = .kilograms
            UserPreferences.energyMeasurementType.value = .kilojoules
        } else {
            UserPreferences.distanceMeasurementType.value = .miles
            UserPreferences.altitudeMeasurementType.value = .feet
            UserPreferences.speedMeasurementType.value = .minutesPerLengthUnit(from: .miles)
            UserPreferences.weightMeasurementType.value = .pounds
            UserPreferences.energyMeasurementType.value = .kilocalories
        }
    }
}
