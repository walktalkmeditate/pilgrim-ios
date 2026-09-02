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
    @Published var honorWaysPresented = false
    @Published var honorOverviewWay: Way?

    /// A Way waiting for the sheet in front of it to finish closing, and a Way
    /// waiting for the overview to finish closing before its walk begins.
    /// Both exist because of AF60 — see `openOverview(for:)`.
    var pendingHonorWay: Way?
    var pendingStartWay: Way?

    private var pendingSnapshot: TempWalk?
    private var bannerDismissWork: DispatchWorkItem?

    init() {
        checkForRecovery()
        // `init()` isn't itself main-actor-isolated (see the `Task { @MainActor
        // in ... }` hops elsewhere in this file) — hop over the same way to
        // reach the backfill's guaranteed main-actor invocation.
        Task { @MainActor in ThreadsBackfill.runIfNeeded() }
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

    func startWalk(mode: WalkMode = .wander, way: Way? = nil) {
        guard activeWalkViewModel == nil else { return }
        let locationStatus = CLLocationManager().authorizationStatus
        if locationStatus == .denied || locationStatus == .restricted {
            showLocationDenied = true
            return
        }
        Task { @MainActor in TranscriptionService.shared.autoTranscriptionSkippedReason = nil }
        let vm = ActiveWalkViewModel(mode: mode, way: way)
        vm.onWalkCompleted = { [weak self, weak vm] snapshot in
            snapshot.comment = vm?.intention
            DataManager.saveWalk(object: snapshot) { success, _, walk in
                if success {
                    // The save transaction is confirmed — only now is the
                    // crash-recovery checkpoint safe to discard (AF1). On
                    // failure it stays on disk and recoverIfNeeded re-saves
                    // the walk at next launch.
                    WalkSessionGuard.deleteCheckpointFile()
                }
                guard let self else { return }
                if success {
                    snapshot.uuid = walk?.uuid
                    // The only place a walk is bound to its Way: `save` is
                    // idempotent (an own-walk Way is first written here), and
                    // `link` overwrites, so it must not run again elsewhere.
                    if let way, let uuid = walk?.uuid {
                        try? WayStore.shared.save(way)
                        let arrival = vm?.honorArrival.map { (theirSeconds: $0.theirSeconds, yourSeconds: $0.yourSeconds) }
                        try? WayStore.shared.link(walkUUID: uuid, to: way.id, arrival: arrival)
                    }
                    self.pendingSnapshot = snapshot
                    self.activeWalkViewModel = nil
                    self.triggerAutoTranscription(for: snapshot)
                    self.requestReviewIfAppropriate()
                    CollectiveCounterService.shared.recordWalk(
                        walkUUID: snapshot.uuid,
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

    /// AF60: the share path must NOT set `completedSnapshot` and the share
    /// URL in the same update — two sibling `.sheet(item:)` presentations
    /// requested simultaneously race, and one is dropped. Dismiss the seal,
    /// hold the snapshot, and let the share sheet present alone; the summary
    /// is promoted from `handleSealShareDismiss` once the share sheet closes.
    func handleSealShare() {
        showSealReveal = false
        if let walk = sealRevealWalk {
            pendingSnapshot = walk
            sealRevealWalk = nil
        }
    }

    func handleSealShareDismiss() {
        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            completedSnapshot = snapshot
        }
    }

    func handleSummaryDismiss() {
        Task { @MainActor in TranscriptionService.shared.autoTranscriptionSkippedReason = nil }
        homeViewModel.loadWalks()
        promotePendingHonorWay()
    }

    // MARK: - Honor

    func chooseWay() {
        honorWaysPresented = true
    }

    /// From the Ways sheet: park the Way, close the sheet, promote on dismiss.
    /// From a link with no sheet open: present directly (one change).
    func openOverview(for way: Way) {
        if honorWaysPresented {
            pendingHonorWay = way
            honorWaysPresented = false
        } else {
            honorOverviewWay = way
        }
    }

    /// Called from a summary's "walk this again": hold the Way, let the
    /// summary sheet close, then present (AF60: never two sheets at once).
    func walkAgain(_ walk: WalkInterface) {
        pendingHonorWay = OwnWalkWayBuilder.make(from: walk)
    }

    func promotePendingHonorWay() {
        if let way = pendingHonorWay {
            pendingHonorWay = nil
            honorOverviewWay = way
        }
    }

    func startHonor(way: Way) {
        pendingStartWay = way
        honorOverviewWay = nil
    }

    func handleOverviewDismiss() {
        if let way = pendingStartWay {
            pendingStartWay = nil
            startWalk(mode: .honor, way: way)
        }
    }

    private func requestReviewIfAppropriate() {
        #if DEBUG
        if CommandLine.arguments.contains("--demo-mode") { return }
        #endif
        let count = (try? DataManager.dataStack.fetchCount(From<Walk>())) ?? 0
        guard count >= 3 else { return }
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            Task { @MainActor in AppStore.requestReview(in: scene) }
        }
    }

    private func triggerAutoTranscription(for snapshot: TempWalk) {
        guard UserPreferences.autoTranscribe.value,
              !snapshot.voiceRecordings.isEmpty else { return }

        // Safe to assume: saveWalk completions land on the main queue
        // (CoreStore's default), same as the other completions in this file.
        let batteryOK = MainActor.assumeIsolated { BatteryGate.allowsBackgroundWork() }

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
        HomeView(
            viewModel: coordinator.homeViewModel,
            onWalkAgain: coordinator.walkAgain,
            onSummaryDismiss: coordinator.promotePendingHonorWay
        )
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
