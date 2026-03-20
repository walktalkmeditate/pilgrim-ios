import SwiftUI
import CoreStore

struct SettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()
    @State private var walkCount = 0
    @State private var totalDistance: Double = 0
    @State private var totalMeditationSeconds: TimeInterval = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.big) {
                    PracticeSummaryHeader(
                        walkCount: walkCount,
                        totalDistanceMeters: totalDistance,
                        totalMeditationSeconds: totalMeditationSeconds
                    )
                    PracticeCard()
                    AtmosphereCard()
                    VoiceCard()
                    PermissionsCard(permissionVM: permissionVM)
                    DataCard()
                    aboutLink
                }
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.bottom, Constants.UI.Padding.breathingRoom)
            }
            .background(Color.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
            }
            .onAppear {
                permissionVM.refresh()
                loadStats()
            }
        }
    }

    // MARK: - About

    private var aboutLink: some View {
        NavigationLink {
            AboutView()
        } label: {
            settingNavRow(label: "About")
        }
        .settingsCard()
    }

    // MARK: - Stats

    private func loadStats() {
        do {
            let walks = try DataManager.dataStack.fetchAll(
                From<Walk>()
            )
            walkCount = walks.count
            totalDistance = walks.reduce(0.0) { $0 + $1.distance }
            totalMeditationSeconds = walks.reduce(0.0) { $0 + $1.meditateDuration }
        } catch {
            walkCount = 0
            totalDistance = 0
            totalMeditationSeconds = 0
        }
    }
}
