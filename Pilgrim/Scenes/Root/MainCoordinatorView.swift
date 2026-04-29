import SwiftUI
import UIKit
import CoreLocation
import CoreStore
import StoreKit

class MainCoordinator: ObservableObject {

    let homeViewModel = HomeViewModel()
    @Published var activeWalkViewModel: ActiveWalkViewModel?
    @Published var completedSnapshot: TempWalk?
    @Published var showSealReveal = false
    @Published var sealRevealWalk: TempWalk?
    @Published var showSaveError = false
    @Published var showLocationDenied = false
    @Published var recoveredWalkDate: Date?

    private var pendingSnapshot: TempWalk?
    private var bannerDismissWork: DispatchWorkItem?

    init() {
        checkForRecovery()
    }

    private func checkForRecovery() {
        WalkSessionGuard.recoverIfNeeded { [weak self] date in
            DispatchQueue.main.async { [weak self] in
                guard let self, let date else { return }
                self.recoveredWalkDate = date
                self.homeViewModel.loadWalks()
                self.bannerDismissWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.recoveredWalkDate = nil
                }
                self.bannerDismissWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
            }
        }
    }

    deinit {
        bannerDismissWork?.cancel()
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func startWalk(mode: WalkMode = .wander) {
        guard activeWalkViewModel == nil else { return }
        let locationStatus = CLLocationManager().authorizationStatus
        if locationStatus == .denied || locationStatus == .restricted {
            showLocationDenied = true
            return
        }
        Task { @MainActor in TranscriptionService.shared.autoTranscriptionSkippedReason = nil }
        let vm = ActiveWalkViewModel()
        vm.onWalkCompleted = { [weak self, weak vm] snapshot in
            snapshot.comment = vm?.intention
            DataManager.saveWalk(object: snapshot) { success, _, walk in
                guard let self else { return }
                if success {
                    snapshot.uuid = walk?.uuid
                    self.pendingSnapshot = snapshot
                    self.activeWalkViewModel = nil
                    self.triggerAutoTranscription(for: snapshot)
                    self.requestReviewIfAppropriate()
                    CollectiveCounterService.shared.recordWalk(
                        distanceKm: snapshot.distance / 1000,
                        meditationMin: Int(snapshot.meditateDuration / 60),
                        talkMin: Int(snapshot.talkDuration / 60)
                    )
                } else {
                    self.showSaveError = true
                }
            }
        }
        activeWalkViewModel = vm
    }

    func cancelWalk() {
        activeWalkViewModel?.cancel()
        activeWalkViewModel = nil
        pendingSnapshot = nil
        Task { @MainActor in TranscriptionService.shared.autoTranscriptionSkippedReason = nil }
    }

    func handleActiveWalkDismiss() {
        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            sealRevealWalk = snapshot
            showSealReveal = true
        } else {
            Task { @MainActor in TranscriptionService.shared.autoTranscriptionSkippedReason = nil }
        }
    }

    func handleSealRevealDismiss() {
        showSealReveal = false
        if let walk = sealRevealWalk {
            completedSnapshot = walk
            sealRevealWalk = nil
        }
    }

    func handleSummaryDismiss() {
        Task { @MainActor in TranscriptionService.shared.autoTranscriptionSkippedReason = nil }
        homeViewModel.loadWalks()
    }

    private func requestReviewIfAppropriate() {
        #if DEBUG
        if CommandLine.arguments.contains("--demo-mode") { return }
        #endif
        let count = (try? DataManager.dataStack.fetchCount(From<Walk>())) ?? 0
        guard count >= 3 else { return }
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    private func triggerAutoTranscription(for snapshot: TempWalk) {
        guard UserPreferences.autoTranscribe.value,
              !snapshot.voiceRecordings.isEmpty else { return }

        let wasMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        UIDevice.current.isBatteryMonitoringEnabled = wasMonitoring
        let batteryOK = level < 0 || level > 0.2 || batteryState == .charging || batteryState == .full

        if batteryOK {
            Task {
                await VoiceEnhancer.shared.waitForPendingWork()
                _ = await TranscriptionService.shared.transcribeRecordings(snapshot.voiceRecordings)
            }
        } else {
            Task { @MainActor in
                TranscriptionService.shared.autoTranscriptionSkippedReason = .lowBattery
            }
        }
    }
}

struct MainCoordinatorView: View {

    @ObservedObject var coordinator: MainCoordinator

    var body: some View {
        HomeView(viewModel: coordinator.homeViewModel)
    }
}

struct RecoveryBanner: View {

    let date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Text(String(format: LS["Recovery.WalkRecovered"], Self.formatter.string(from: date)))
            .font(Constants.Typography.caption)
            .foregroundColor(Color(.ink))
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.vertical, Constants.UI.Padding.small)
            .background(Color(.parchmentSecondary).opacity(0.95))
            .cornerRadius(8)
            .padding(.top, Constants.UI.Padding.small)
    }
}
