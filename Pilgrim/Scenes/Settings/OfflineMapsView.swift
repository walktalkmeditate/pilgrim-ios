// Pilgrim/Scenes/Settings/OfflineMapsView.swift
import SwiftUI

// Every caller — the view's own reload, the Data card, the tests — is
// already on the main actor, the same actor `PilgrimageTilesManager` and
// `PilgrimagePackageManager` are pinned to.
@MainActor
enum OfflineMapsModel {

    struct Saved: Equatable {
        let routeName: String
        let bytes: Int
        let savedStages: Int
        let totalStages: Int
    }

    static let emptyCaption = "no maps saved"
    static let deleteTitle = "Delete maps?"
    static let deleteMessage = "Removes the saved basemap. The route's stages stay on your phone."

    static func rowDetail(_ saved: Saved?) -> String {
        guard let saved else { return "none saved" }
        return "\(saved.routeName) · \(PilgrimageMapsRowModel.megabytes(saved.bytes))"
    }

    /// Nil when no stage of the installed route has a saved region. A
    /// partial save is still bytes on the phone, so it is reported.
    static func load(routeName: String, routeId: String, stages: [Way], tiles: PilgrimageTilesManager) -> Saved? {
        let savedStages = stages.filter(tiles.isStageSaved)
        guard !savedStages.isEmpty else { return nil }
        // One store read for the whole route: `regions()` refreshes the
        // loader's cache, so asking it per stage re-reads once per stage.
        let byId = Dictionary(tiles.loader.regions().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let bytes = savedStages.compactMap { byId[$0.id] }.reduce(0) { $0 + $1.completedResourceSize }
        return Saved(routeName: routeName, bytes: bytes, savedStages: savedStages.count, totalStages: stages.count)
    }

    /// What the Data card and this view both read: the installed route's
    /// stages through the tiles manager.
    static func loadInstalled(packages: PilgrimagePackageManager, tiles: PilgrimageTilesManager) -> (saved: Saved?, routeId: String?) {
        guard let installed = packages.installed() else { return (nil, nil) }
        let stages = (0..<installed.route.stageCount).compactMap {
            packages.store.load(id: WayStore.stageWayId(routeId: installed.routeId, stageIndex: $0))
        }
        return (load(routeName: installed.route.name, routeId: installed.routeId, stages: stages, tiles: tiles), installed.routeId)
    }
}

/// Settings → Data → Maps. Written for one pilgrimage, because that is
/// all the phone ever holds. It never starts a save: the route page's
/// button is the one door to that tap.
struct OfflineMapsView: View {

    @ObservedObject private var tiles = PilgrimageTilesManager.shared
    @State private var saved: OfflineMapsModel.Saved?
    @State private var routeId: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let saved {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.routeName).font(Constants.Typography.body).foregroundColor(.ink)
                    Text("\(PilgrimageMapsRowModel.megabytes(saved.bytes)) · \(saved.savedStages) of \(saved.totalStages) stages")
                        .font(Constants.Typography.caption).foregroundColor(.fog)
                }
                Button("Delete maps", role: .destructive) { confirmDelete = true }
                    .font(Constants.Typography.button)
            } else {
                Text(OfflineMapsModel.emptyCaption).font(Constants.Typography.caption).foregroundColor(.fog)
            }
        }
        .navigationTitle("Maps")
        .onAppear(perform: reload)
        .alert(OfflineMapsModel.deleteTitle, isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let routeId { tiles.remove(routeId: routeId) }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OfflineMapsModel.deleteMessage)
        }
    }

    private func reload() {
        let loaded = OfflineMapsModel.loadInstalled(packages: PilgrimagePackageManager.shared, tiles: tiles)
        saved = loaded.saved
        routeId = loaded.routeId
    }
}
