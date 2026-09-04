import SwiftUI

enum PilgrimageCatalogModel {

    /// "ES · 764 km · 33 stages", or, once the package is here, the route's
    /// own progress instead of the bare stage count.
    static func card(entry: PilgrimageCatalogEntry, ledger: PilgrimageLedger?, isInstalled: Bool) -> String {
        var parts: [String] = []
        if let country = entry.country, !country.isEmpty { parts.append(country) }
        parts.append(StatsHelper.string(for: entry.distanceKm * 1000, unit: UnitLength.meters, type: .distance))
        if isInstalled {
            parts.append("on your phone")
            parts.append(PilgrimageLedger.progressLine(ledger: ledger, stageCount: entry.stageCount))
        } else {
            parts.append(entry.stageCount == 1 ? "1 stage" : "\(entry.stageCount) stages")
        }
        return parts.joined(separator: " · ")
    }

    /// The build marks a route sparse when fewer than half its stages carry
    /// a curated place beyond the start and end towns. The route is still
    /// walkable and still listed — this is the honest caption that keeps it
    /// from promising more than it holds.
    static func sparseNote(for entry: PilgrimageCatalogEntry) -> String? {
        entry.sparse ? "few places marked yet" : nil
    }
}

/// The third door: the routes the dataset says are walkable. A route with a
/// package on this phone is marked; everything else is an invitation.
struct PilgrimageCatalogView: View {

    let onChoose: (Way) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalogService = PilgrimageCatalogService.shared
    @ObservedObject private var packages = PilgrimagePackageManager.shared
    @State private var isLoading = true
    @State private var failure: PilgrimageError?
    @State private var ledgers: [String: PilgrimageLedger] = [:]
    @State private var installedRouteId: String?
    @State private var opened: PilgrimageCatalogEntry?

    private let ledgerStore = PilgrimageLedgerStore()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pilgrimages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .font(Constants.Typography.button)
                            .foregroundColor(.stone)
                    }
                }
                .navigationDestination(item: $opened) { entry in
                    PilgrimageRouteView(entry: entry,
                                        release: catalogService.catalog?.release ?? "",
                                        onChoose: onChoose)
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, catalogService.catalog == nil {
            // SwiftUI's, not the project's own ProgressView.
            SwiftUI.ProgressView()
                .tint(.stone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let routes = catalogService.catalog?.routes, !routes.isEmpty {
            List(routes) { entry in
                Button { opened = entry } label: { row(entry) }
            }
        } else {
            unreachable
        }
    }

    private var unreachable: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Text(PilgrimageCopy.line(for: failure ?? .catalogUnreachable))
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
            Button("try again") { Task { await load(force: true) } }
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
                .frame(minHeight: 44)
        }
        .padding(Constants.UI.Padding.big)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: PilgrimageCatalogEntry) -> some View {
        HStack(alignment: .top, spacing: Constants.UI.Padding.normal) {
            coverPlate(entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(PilgrimageCatalogModel.card(entry: entry, ledger: ledgers[entry.id],
                                                 isInstalled: installedRouteId == entry.id))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                if let sparseNote = PilgrimageCatalogModel.sparseNote(for: entry) {
                    Text(sparseNote)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.7))
                }
            }
        }
    }

    /// The dataset ships no cover images yet (spec open question 1), so the
    /// plate stands where one will go rather than leaving the row lopsided.
    private func coverPlate(_ entry: PilgrimageCatalogEntry) -> some View {
        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
            .fill(Color.parchmentSecondary)
            .frame(width: 44, height: 44)
            .overlay(
                Text(entry.name.prefix(1))
                    .font(Constants.Typography.heading)
                    .foregroundColor(.stone)
            )
            .accessibilityHidden(true)
    }

    private func load(force: Bool = false) async {
        isLoading = true
        failure = nil
        do {
            let catalog = try await catalogService.load(force: force)
            installedRouteId = packages.installed()?.routeId
            ledgers = Dictionary(uniqueKeysWithValues: catalog.routes.compactMap { entry in
                ledgerStore.load(routeId: entry.id).map { (entry.id, $0) }
            })
        } catch {
            failure = (error as? PilgrimageError) ?? .catalogUnreachable
        }
        isLoading = false
    }
}
