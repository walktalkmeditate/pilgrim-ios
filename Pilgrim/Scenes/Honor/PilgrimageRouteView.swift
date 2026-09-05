import SwiftUI

/// "24 km · 1,400 m up · 7 to 9 hours · hard" — the one stage-facts line,
/// shared by the route screen's stage list and the morning card. Two copies
/// of this drifted apart once already.
enum WayStageFacts {

    static func line(distanceKm: Double, gainMeters: Double, hours: WayStageHours, difficulty: String) -> String {
        var parts = [
            StatsHelper.string(for: distanceKm * 1000, unit: UnitLength.meters, type: .distance),
            "\(StatsHelper.string(for: gainMeters, unit: UnitLength.meters, type: .altitude)) up",
            hoursText(hours)
        ]
        if !difficulty.isEmpty { parts.append(difficulty) }
        return parts.joined(separator: " · ")
    }

    /// `Int(_:)` traps on a non-finite Double; the importer already bounds
    /// these, and this is the last step before the number reaches the screen.
    private static func hoursText(_ hours: WayStageHours) -> String {
        let low = boundedHours(hours.min)
        let high = boundedHours(hours.max)
        return low == high ? "\(low) hours" : "\(low) to \(high) hours"
    }

    /// An infinite figure is an absurdly large one and clamps to the ceiling
    /// like any other; a NaN orders against nothing, so `min`/`max` would
    /// carry it straight through to the trap and it takes the floor instead.
    private static func boundedHours(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(min(max(value, 0), 100).rounded())
    }
}

enum PilgrimageRouteModel {

    static let redrawNotice = "the route's stages were redrawn; your kilometres are kept."

    static func stageLine(_ stage: PilgrimageRouteStage) -> String {
        WayStageFacts.line(distanceKm: stage.distanceKm, gainMeters: stage.gainMeters,
                           hours: stage.hours, difficulty: stage.difficulty)
    }

    static func nextRow(ledger: PilgrimageLedger?, stageCount: Int) -> String {
        guard let next = (ledger ?? PilgrimageLedger(routeId: "")).next(stageCount: stageCount) else {
            return "you have walked the whole way"
        }
        if next.resumeFrac != nil { return "continue from where you stopped" }
        return next.index == 0 ? "start with stage 1" : "next: stage \(next.index + 1)"
    }

    static func buttonLabel(isInstalled: Bool, hasUpdate: Bool) -> String {
        if !isInstalled { return "Download" }
        return hasUpdate ? "Update" : "On your phone"
    }
}

/// One route: what it is, where you are in it, and every stage it divides
/// into. A downloaded stage opens the Honor overview with Begin.
struct PilgrimageRouteView: View {

    let entry: PilgrimageCatalogEntry
    let release: String
    let onChoose: (Way) -> Void

    @ObservedObject private var packages = PilgrimagePackageManager.shared
    @State private var route: PilgrimageRoute?
    @State private var ledger: PilgrimageLedger?
    @State private var installed: PilgrimagePackageManager.Installed?
    @State private var failure: PilgrimageError?
    /// The stage list is fetched separately when nothing is downloaded yet;
    /// its own two states, so a failed preview does not read as a failed
    /// download.
    @State private var isLoadingStages = false
    @State private var stagesFailure: PilgrimageError?
    @State private var confirmReplace = false
    @State private var confirmRemove = false
    @State private var showRedrawNotice = false
    @State private var promptDownload = false

    private let ledgerStore = PilgrimageLedgerStore()

    private var isInstalled: Bool { installed?.routeId == entry.id }
    /// From the cached `installed` state `reload()` already reads — never
    /// `packages.hasUpdate`, which reparses `route.json` off disk and
    /// `downloadButton` alone reads three times on every `phase` publish
    /// during a download.
    private var hasUpdate: Bool { installed.map { $0.routeId == entry.id && $0.release != release } ?? false }
    private var stages: [PilgrimageRouteStage] { route?.stages ?? [] }

    var body: some View {
        List {
            Section { header } footer: { statusFooter }
            if isInstalled {
                Section { nextRow }
            }
            Section {
                stageSection
            } header: {
                Text("Stages").font(Constants.Typography.caption)
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isInstalled {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Remove", role: .destructive) { confirmRemove = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .task {
            reload()
            await loadStagesIfNeeded()
        }
        .alert("Replace?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) { Task { await install(replacing: true) } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(PilgrimagePackageManager.replaceConfirmation(routeName: installed?.route.name ?? "route"))
        }
        .alert("Remove?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { removeRoute() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(PilgrimagePackageManager.removeConfirmation(routeName: entry.name))
        }
        .alert("Download this route first?", isPresented: $promptDownload) {
            // The same gate the download button uses: with another route
            // already on the phone, this is a Replace and must say so.
            Button("Download") { beginInstall() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Its stages have to be on your phone before you can walk one.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            if let summary = route?.summary ?? entryFallbackSummary {
                Text(summary).font(Constants.Typography.body).foregroundColor(.ink)
            }
            // Directly under the summary: what the route can promise, before
            // the button that offers to download it.
            if let sparseNote = PilgrimageCatalogModel.sparseNote(for: entry) {
                Text(sparseNote)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog.opacity(0.7))
            }
            Text(PilgrimageCatalogModel.card(entry: entry, ledger: ledger, isInstalled: isInstalled, hasUpdate: hasUpdate))
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            downloadButton
        }
    }

    private var entryFallbackSummary: String? {
        entry.tradition.map { "\($0.capitalized) · \(entry.region ?? "")" }
    }

    private var downloadButton: some View {
        Button {
            if isInstalled && !hasUpdate { return }
            beginInstall()
        } label: {
            Text(PilgrimageRouteModel.buttonLabel(isInstalled: isInstalled, hasUpdate: hasUpdate))
                .font(Constants.Typography.button)
                .foregroundColor(.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isBusy || (isInstalled && !hasUpdate) ? Color.fog : Color.stone)
                .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .disabled(isBusy || (isInstalled && !hasUpdate))
    }

    @ViewBuilder
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            if case .downloading(let done, let total) = packages.phase {
                // `total` counts `route.json` plus every stage; the pilgrim
                // only cares about stages, so both sides drop the one file
                // that isn't a stage.
                Text("stage \(max(done - 1, 0)) of \(total - 1)").font(Constants.Typography.caption).foregroundColor(.fog)
            }
            if let failure {
                Text(PilgrimageCopy.line(for: failure)).font(Constants.Typography.caption).foregroundColor(.rust)
            }
            if showRedrawNotice {
                Text(PilgrimageRouteModel.redrawNotice).font(Constants.Typography.caption).foregroundColor(.fog)
            }
        }
    }

    private var nextRow: some View {
        Button {
            guard let next = (ledger ?? PilgrimageLedger(routeId: entry.id)).next(stageCount: entry.stageCount)
                ?? stages.first.map({ PilgrimageLedger.Next(index: $0.index, resumeFrac: nil) }) else { return }
            open(index: next.index)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(PilgrimageRouteModel.nextRow(ledger: ledger, stageCount: entry.stageCount))
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(PilgrimageLedger.progressLine(ledger: ledger, stageCount: entry.stageCount))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    /// The stage list stands whether or not the package is here: spec 2.2
    /// wants a row to tap before anything is downloaded.
    @ViewBuilder
    private var stageSection: some View {
        if !stages.isEmpty {
            ForEach(stages, id: \.index) { stage in
                Button { open(stage) } label: { stageRow(stage) }
            }
        } else if isLoadingStages {
            HStack {
                SwiftUI.ProgressView().tint(.stone)
                Text("reaching for the stages…")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        } else if let stagesFailure {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                Text(PilgrimageCopy.line(for: stagesFailure))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Button("try again") { Task { await loadStagesIfNeeded(force: true) } }
                    .font(Constants.Typography.caption)
                    .foregroundColor(.stone)
                    .frame(minHeight: 44)
            }
        }
    }

    private func stageRow(_ stage: PilgrimageRouteStage) -> some View {
        HStack(alignment: .top, spacing: Constants.UI.Padding.small) {
            Image(systemName: ledger?.stages[String(stage.index)]?.completed == true ? "circle.fill" : "circle")
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stage.index + 1). \(stage.name)")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(PilgrimageRouteModel.stageLine(stage))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Actions

    private var isBusy: Bool {
        if case .downloading = packages.phase { return true }
        return false
    }

    private func open(_ stage: PilgrimageRouteStage) { open(index: stage.index) }

    private func open(index: Int) {
        guard isInstalled,
              let way = WayStore.shared.load(id: WayStore.stageWayId(routeId: entry.id, stageIndex: index)) else {
            promptDownload = true
            return
        }
        onChoose(way)
    }

    /// Every path that starts an install goes through here, so the Replace
    /// confirmation can never be skipped by tapping a stage instead of the
    /// button.
    private func beginInstall() {
        if installed != nil && !isInstalled {
            confirmReplace = true
        } else {
            Task { await install(replacing: false) }
        }
    }

    private func install(replacing: Bool) async {
        failure = nil
        do {
            if hasUpdate {
                try await packages.update(entry: entry, release: release)
            } else if replacing {
                try await packages.replace(with: entry, release: release)
            } else {
                try await packages.download(entry: entry, release: release)
            }
            failure = nil
        } catch {
            failure = (error as? PilgrimageError) ?? .incomplete
        }
        // Reload on both branches: a failed update's rollback removed the
        // package, and only reload() picks that state back up so the screen
        // never keeps showing the pre-rollback "on your phone" state.
        reload()
    }

    private func removeRoute() {
        do {
            try packages.remove(routeId: entry.id)
            reload()
        } catch {
            failure = (error as? PilgrimageError) ?? .incomplete
        }
    }

    /// The redraw notice is shown once and then cleared from the ledger, so
    /// the route says it the next time the pilgrim opens this screen and
    /// never again. An installed route's own `route.json` is authoritative;
    /// the preview only fills the gap before one exists.
    private func reload() {
        installed = packages.installed()
        if installed?.routeId == entry.id { route = installed?.route }
        ledger = ledgerStore.load(routeId: entry.id)
        if ledger?.redrawNoticePending == true {
            showRedrawNotice = true
            ledgerStore.clearRedrawNotice(routeId: entry.id)
        }
    }

    /// Fetches the route's stage list when nothing is downloaded, so the
    /// pilgrim can see what they are being offered before they take it.
    private func loadStagesIfNeeded(force: Bool = false) async {
        guard force || route == nil, !release.isEmpty else { return }
        isLoadingStages = true
        stagesFailure = nil
        do {
            route = try await PilgrimageCatalogService.shared.routePreview(entry: entry, release: release)
        } catch {
            stagesFailure = (error as? PilgrimageError) ?? .catalogUnreachable
        }
        isLoadingStages = false
    }
}
