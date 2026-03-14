import SwiftUI

struct SettingsView: View {

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Distance")
                            .font(Constants.Typography.body)
                        Spacer()
                        Text("Kilometers")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    HStack {
                        Text("Speed")
                            .font(Constants.Typography.body)
                        Spacer()
                        Text("min/km")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                } header: {
                    Text("Units")
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
}
