import SwiftUI

struct SettingsView: View {

    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers

    var body: some View {
        NavigationStack {
            List {
                Section {
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

                    unitRow(label: "Distance", value: isMetric ? "km" : "mi")
                    unitRow(label: "Speed", value: isMetric ? "min/km" : "min/mi")
                    unitRow(label: "Elevation", value: isMetric ? "m" : "ft")
                } header: {
                    Text("Units")
                        .font(Constants.Typography.caption)
                }

                Section {
                    NavigationLink {
                        SoundSettingsView()
                    } label: {
                        HStack {
                            Text("Sounds")
                                .font(Constants.Typography.body)
                            Spacer()
                            Text(UserPreferences.soundsEnabled.value ? "On" : "Off")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                } header: {
                    Text("Audio")
                        .font(Constants.Typography.caption)
                }

                Section {
                    HStack {
                        Text("Version")
                            .font(Constants.Typography.body)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                } header: {
                    Text("About")
                        .font(Constants.Typography.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
            }
        }
    }

    private func unitRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
            Spacer()
            Text(value)
                .font(Constants.Typography.caption)
                .foregroundColor(.ink)
        }
    }

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
