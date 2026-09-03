import Combine
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
    @Published var honorImportState: HonorImportState = .idle
    /// The only feedback a link has when no Honor sheet is open to carry it.
    @Published var pendingLinkToast: String?

    /// A Way waiting for the sheet in front of it to finish closing, and a Way
    /// waiting for the overview to finish closing before its walk begins.
    /// Both exist because of AF60 — see `openOverview(for:)`.
    var pendingHonorWay: Way?
    var pendingStartWay: Way?

    private var pendingSnapshot: TempWalk?
    private var bannerDismissWork: DispatchWorkItem?
    private var linkToastWork: DispatchWorkItem?
    private var importTask: Task<Void, Never>?
    private var gatheringCancellable: AnyCancellable?

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
        linkToastWork?.cancel()
        importTask?.cancel()
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func startWalk(mode: WalkMode = .wander, way: Way? = nil) {
        guard activeWalkViewModel == nil else { return }
        // The overview is gone by the time a walk starts, so nothing is left
        // to render an import: a Way's gathering must not outlive its sheet.
        importTask?.cancel()
        importTask = nil
        gatheringCancellable = nil
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

    /// Resets the import state and any toast left over from a previous link
    /// so a stale failure line never greets the next opening of the sheet.
    func chooseWay() {
        honorImportState = .idle
        showLinkToast(nil)
        honorWaysPresented = true
    }

    /// Fetch happens wherever the user is: inside the Ways sheet the state
    /// renders inline beside the paste field (a not-found error keeps the
    /// field editable); from a link with no sheet open, a toast carries it.
    func openWay(shareId: String) {
        guard activeWalkViewModel == nil else { showLinkToast("finish this walk first"); return }
        importTask?.cancel()
        honorImportState = .fetching
        if !honorWaysPresented { showLinkToast("reaching for the walk…") }
        importTask = Task { @MainActor [weak self] in
            do {
                let way = try await WayImporter().importShare(id: shareId)
                // A cancelled import belongs to a link the walker has already
                // replaced; neither its Way nor its error may land on top of
                // the newer one's state.
                guard let self, !Task.isCancelled else { return }
                self.showLinkToast(nil)
                self.honorImportState = .idle
                self.importTask = nil
                // A Begin already in flight (a walk starting, or parked to
                // start once the overview closes) wins — presenting this Way
                // now would race it for the overview sheet or interrupt the
                // walk that's already beginning. Drop it silently.
                guard self.activeWalkViewModel == nil, self.pendingStartWay == nil else { return }
                self.openOverview(for: way)      // AF60-safe: parks or presents, never both
            } catch {
                guard let self, !Task.isCancelled else { return }
                let failure = (error as? WayError) ?? .unavailable
                self.honorImportState = .failed(failure)
                self.showLinkToast(self.honorWaysPresented ? nil : HonorImportCopy.line(for: .failed(failure)))
                self.importTask = nil
            }
        }
    }

    /// From the Ways sheet: park the Way, close the sheet, promote on dismiss.
    /// From a link with no sheet open: present directly (one change).
    func openOverview(for way: Way) {
        if honorWaysPresented {
            pendingHonorWay = way
            honorWaysPresented = false
        } else {
            honorOverviewWay = way
            gather(way)
        }
    }

    /// Drives the downloader's published sets into `honorImportState` for the
    /// Way the overview is showing. Hops to the main actor rather than being
    /// isolated to it, so the nonisolated presentation calls above can reach
    /// the (main-actor) downloader without each repeating the hop.
    func gather(_ way: Way) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A dismiss or an item swap that lands before this hop must not
            // install a sink for a Way that is no longer showing.
            guard self.honorOverviewWay?.id == way.id else { return }
            guard case .share = way.source else { self.honorImportState = .ready; return }
            let downloader = WayMediaDownloader.shared
            downloader.download(way)
            self.honorImportState = HonorImportReducer.state(
                wayId: way.id, progress: downloader.progress, active: downloader.active,
                failures: downloader.failures, diskFull: downloader.diskFull)
            self.gatheringCancellable = downloader.$progress
                .combineLatest(downloader.$active, downloader.$failures, downloader.$diskFull)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] progress, active, failures, diskFull in
                    self?.honorImportState = HonorImportReducer.state(
                        wayId: way.id, progress: progress, active: active, failures: failures, diskFull: diskFull)
                }
        }
    }

    func retryMedia(for way: Way) {
        Task { @MainActor in WayMediaDownloader.shared.retry(way) }
    }

    /// "walk without the missing voices": the sink is dropped first, so a
    /// later change from another Way's download can't recompute this one back
    /// into `.mediaMissing`. The absent files simply never play.
    func walkWithoutMissingVoices() {
        gatheringCancellable = nil
        honorImportState = .ready
    }

    /// Called from a summary's "walk this again": hold the Way, let the
    /// summary sheet close, then present (AF60: never two sheets at once).
    /// A nil build (OwnWalkWayBuilder.make(from:) rejecting too short a route or a missing uuid) parks nothing and no overview appears; every host wiring `onWalkAgain` must also wire its summary's `onDismiss` to `promotePendingHonorWay`, since the park is global but the promote is per-host.
    func walkAgain(_ walk: WalkInterface) {
        pendingHonorWay = OwnWalkWayBuilder.make(from: walk)
    }

    func promotePendingHonorWay() {
        if let way = pendingHonorWay {
            pendingHonorWay = nil
            honorOverviewWay = way
            gather(way)
        }
    }

    func startHonor(way: Way) {
        pendingStartWay = way
        honorOverviewWay = nil
    }

    func handleOverviewDismiss() {
        // A link arriving while the overview is open swaps the sheet's item
        // rather than closing it, and this fires for the outgoing Way after
        // the incoming one's gathering has already begun. Reset only on a
        // real close.
        if honorOverviewWay == nil {
            gatheringCancellable = nil
            honorImportState = .idle
        }
        if let way = pendingStartWay {
            pendingStartWay = nil
            startWalk(mode: .honor, way: way)
        }
    }

    /// One toast at a time, always with a cancellable expiry: a link that
    /// never resolves must not leave "reaching for the walk…" on screen.
    private func showLinkToast(_ text: String?) {
        linkToastWork?.cancel()
        pendingLinkToast = text
        guard text != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.pendingLinkToast = nil }
        linkToastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
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

/// What a link says when no Honor sheet is open to say it inline.
struct HonorLinkToast: View {

    let text: String

    var body: some View {
        Text(text)
            .font(Constants.Typography.caption)
            .foregroundColor(Color(.ink))
            .multilineTextAlignment(.center)
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.vertical, Constants.UI.Padding.small)
            .background(Color(.parchmentSecondary).opacity(0.95))
            .cornerRadius(8)
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.small)
            .allowsHitTesting(false)
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
