import SwiftUI

struct GeneralSettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()
    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers
    @State private var beginWithIntention = UserPreferences.beginWithIntention.value
    @State private var celestialAwareness = UserPreferences.celestialAwarenessEnabled.value
    @State private var zodiacSystem = UserPreferences.zodiacSystem.value
    @State private var appearanceMode = UserPreferences.appearanceMode.value

    var body: some View {
        List {
            appearanceSection
            walkSection
            celestialSection
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

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
                Spacer()
                Picker("", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: appearanceMode) { _, newValue in
                    UserPreferences.appearanceMode.value = newValue
                }
            }
        } header: {
            Text("Appearance")
                .font(Constants.Typography.caption)
        }
    }

    // MARK: - Walk

    private var walkSection: some View {
        Section {
            Toggle(isOn: $beginWithIntention) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Begin with intention")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text("Set an intention when starting a walk")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.stone)
            .onChange(of: beginWithIntention) { _, newValue in
                UserPreferences.beginWithIntention.value = newValue
            }
        } header: {
            Text("Walk")
                .font(Constants.Typography.caption)
        }
    }

    // MARK: - Celestial Awareness

    private var celestialSection: some View {
        Section {
            Toggle(isOn: $celestialAwareness) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Celestial awareness")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text("Show planetary positions and zodiac context")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.stone)
            .onChange(of: celestialAwareness) { _, newValue in
                UserPreferences.celestialAwarenessEnabled.value = newValue
            }

            if celestialAwareness {
                HStack {
                    Text("Zodiac system")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Spacer()
                    Picker("", selection: $zodiacSystem) {
                        Text("Tropical").tag("tropical")
                        Text("Sidereal").tag("sidereal")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: zodiacSystem) { _, newValue in
                        UserPreferences.zodiacSystem.value = newValue
                    }
                }
            }
        } header: {
            Text("Celestial")
                .font(Constants.Typography.caption)
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
                Text(isMetric ? "km · min/km · m · °C" : "mi · min/mi · ft · °F")
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
        UserPreferences.applyUnitSystem(metric: metric)
    }
}
