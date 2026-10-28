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
    @Published var honorRouteLink: HonorRouteLink?

    /// A Way waiting for the sheet in front of it to finish closing, and a Way
    /// waiting for the overview to finish closing before its walk begins.
    /// Both exist because of AF60 — see `openOverview(for:)`.
    var pendingHonorWay: Way?
    var pendingStartWay: Way?
    /// A route screen waiting for the sheet in front of it to finish closing.
    /// AF60 again: see `openRouteLink(_:)`.
    var pendingRouteLink: HonorRouteLink?

    /// Injectable so a spec can hold an import open across a Begin or a walk
    /// start and pin what the resolution is allowed to do. Production always
    /// gets the real importer.
    var importShare: (String) async throws -> Way = { try await WayImporter().importShare(id: $0) }
    /// Injectable so a spec can point the ledger at a temporary directory.
    var pilgrimageLedgers = PilgrimageLedgerStore()
    /// Injectable so a spec can say what is on the phone and what the
    /// catalog holds without a package on disk or a network. Production
    /// reads the real managers.
    var installedRouteId: @MainActor () -> String? = { PilgrimagePackageManager.shared.installed()?.routeId }
    var loadStageWay: (String) -> Way? = { WayStore.shared.load(id: $0) }
    var cachedCatalog: @MainActor () -> PilgrimageCatalog? = { PilgrimageCatalogService.shared.catalog }
    var loadCatalog: @MainActor () async throws -> PilgrimageCatalog = { try await PilgrimageCatalogService.shared.load() }

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
        // to render an import's progress — only the OBSERVATION is dropped.
        // The background transfers keep running, and a file that lands
        // mid-walk becomes playable like any other.
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
                    // The only place a finished walk is bound to its Way:
                    // `save` is idempotent (an own-walk Way is first written
                    // here), and `link` overwrites, so it must not run again
                    // elsewhere. Crash recovery binds too, but only a walk
                    // this path never reached, so the two can't collide.
                    // A packaged stage is skipped — this `way` was captured at
                    // Begin, and an Update that redrew the stage while the
                    // walk was on would be written back over here.
                    if let way, let uuid = walk?.uuid {
                        if !way.source.isPackageOwned { try? WayStore.shared.save(way) }
                        let arrival = vm?.honorArrival.map { (theirSeconds: $0.theirSeconds, yourSeconds: $0.yourSeconds) }
                        try? WayStore.shared.link(walkUUID: uuid, to: way.id, arrival: arrival)
                        self.recordStageWalk(way: way, outcome: vm?.honorStageOutcome)
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
        wirePilgrimageManagers()
        honorImportState = .idle
        showLinkToast(nil)
        honorWaysPresented = true
    }

    /// Downloading a second route, Replace, Update, and Remove are all
    /// refused while a walk is on; this is where the managers learn what
    /// "on" means, and where Replace and Remove learn to take the maps with
    /// them. A stage link reaches the route screen without the Ways sheet,
    /// so both doors call this.
    private func wirePilgrimageManagers() {
        Task { @MainActor in
            PilgrimagePackageManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
            PilgrimageTilesManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
            PilgrimagePackageManager.shared.tiles = PilgrimageTilesManager.shared
        }
    }

    /// Fetch happens wherever the user is: inside the Ways sheet the state
    /// renders inline beside the paste field (a not-found error keeps the
    /// field editable); from a link with no sheet open, a toast carries it.
    func openWay(shareId: String) {
        guard activeWalkViewModel == nil else { showLinkToast("finish this walk first"); return }
        importTask?.cancel()
        honorImportState = .fetching
        if !honorWaysPresented { showLinkToast("reaching for the walk…") }
        let fetch = importShare
        importTask = Task { @MainActor [weak self] in
            do {
                let way = try await fetch(shareId)
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

    /// A stage link does what tapping that stage on the route screen does:
    /// its overview if the route is on the phone, otherwise the route screen
    /// with the stage in view. It shares `importTask` with share links, so
    /// the newest link of either kind wins.
    func openStage(routeId: String, index: Int) {
        guard activeWalkViewModel == nil else { showLinkToast("finish this walk first"); return }
        importTask?.cancel()
        // The share import this replaces will never land, so its spinner
        // must not wait for the Ways sheet's next opening.
        if honorImportState == .fetching { honorImportState = .idle }
        wirePilgrimageManagers()
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let installed = self.installedRouteId()
            let way = installed == routeId
                ? self.loadStageWay(WayStore.stageWayId(routeId: routeId, stageIndex: index))
                : nil
            func resolve(_ catalog: PilgrimageCatalog?) -> StageLinkOutcome {
                StageLinkResolver.resolve(routeId: routeId, index: index, installedRouteId: installed,
                                          stageWayExists: way != nil, catalog: catalog)
            }
            var outcome = resolve(self.cachedCatalog())
            if outcome == .needsCatalog {
                self.showLinkToast("reaching for the route…")
                do {
                    let catalog = try await self.loadCatalog()
                    guard !Task.isCancelled else { return }
                    outcome = resolve(catalog)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.importTask = nil
                    self.showLinkToast(PilgrimageCopy.line(for: (error as? PilgrimageError) ?? .catalogUnreachable))
                    return
                }
            }
            self.importTask = nil
            // A Begin already in flight, or a walk started while the catalog
            // loaded, wins: nothing may interrupt it.
            guard self.activeWalkViewModel == nil, self.pendingStartWay == nil else {
                self.showLinkToast(nil)
                return
            }
            switch outcome {
            case .overview:
                self.showLinkToast(nil)
                if let way { self.openOverview(for: way) }
            case .routeSheet(let link):
                self.showLinkToast(nil)
                self.openRouteLink(link)
            case .notInCatalog, .needsCatalog:
                self.showLinkToast("this route isn't in Pilgrim yet")
            }
        }
    }

    /// AF60: a route screen asked for while the Ways sheet, a summary or an
    /// overview is up waits for that sheet to close, and its dismiss
    /// promotes it. An open route sheet is simply swapped, since the link's
    /// id carries its focus.
    func openRouteLink(_ link: HonorRouteLink) {
        if honorWaysPresented || completedSnapshot != nil || honorOverviewWay != nil {
            pendingRouteLink = link
            honorWaysPresented = false
            honorOverviewWay = nil
        } else {
            honorRouteLink = link
        }
    }

    /// From the Ways sheet: park the Way, close the sheet, promote on dismiss.
    /// From a link with no sheet open: present directly (one change).
    func openOverview(for way: Way) {
        // A summary sheet is a presented sheet too: presenting the overview
        // over it drops the overview on the floor and dead-ends the link.
        // `handleSummaryDismiss` promotes the park when the summary closes,
        // exactly as the Ways sheet's dismiss does. Choosing a stage inside
        // the route sheet lands here too.
        if honorWaysPresented || honorRouteLink != nil || completedSnapshot != nil {
            pendingHonorWay = way
            honorWaysPresented = false
            honorRouteLink = nil
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

    /// A finished walk's way into the route's ledger. Silent for a Way that is
    /// not a stage; the store decides what a stage walk has to have earned.
    func recordStageWalk(way: Way?, outcome: HonorStageOutcome?, at date: Date = Date()) {
        guard let stage = way?.stage else { return }
        pilgrimageLedgers.record(stage: stage, outcome: outcome, at: date)
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
        } else {
            promotePendingRouteLink()
        }
    }

    private func promotePendingRouteLink() {
        guard let link = pendingRouteLink else { return }
        pendingRouteLink = nil
        honorRouteLink = link
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
            pendingRouteLink = nil
            startWalk(mode: .honor, way: way)
        } else if honorOverviewWay == nil {
            // Not on an item swap: the incoming overview is already showing.
            promotePendingRouteLink()
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

    #if DEBUG
    /// Awaits the in-flight import so a spec can assert on what its
    /// resolution was allowed to do, without polling or a deadline.
    func waitForImport() async {
        await importTask?.value
    }
    #endif
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
