import Foundation

/// A route screen opened from a stage link, and the stage it should bring
/// into view. The id carries the focus, so a second link to another stage of
/// the same route re-presents the sheet rather than leaving it where it was.
struct HonorRouteLink: Identifiable, Equatable {
    let entry: PilgrimageCatalogEntry
    let release: String
    let focus: Int?

    var id: String { "\(entry.id):\(focus.map(String.init) ?? "-")" }
}

enum StageLinkOutcome: Equatable {
    case overview(wayId: String)
    case routeSheet(HonorRouteLink)
    case notInCatalog
    case needsCatalog
}

/// What a stage link does, decided without disk or network: the coordinator
/// gathers what is on the phone and what the catalog says, and this names
/// the screen. It is exactly what tapping that stage on the route screen
/// does, so a downloaded stage never waits on the catalog.
enum StageLinkResolver {

    static func resolve(routeId: String, index: Int, installedRouteId: String?,
                        stageWayExists: Bool, catalog: PilgrimageCatalog?) -> StageLinkOutcome {
        if installedRouteId == routeId, stageWayExists {
            return .overview(wayId: WayStore.stageWayId(routeId: routeId, stageIndex: index))
        }
        guard let catalog else { return .needsCatalog }
        guard let entry = catalog.routes.first(where: { $0.id == routeId }) else { return .notInCatalog }
        let focus = (0..<entry.stageCount).contains(index) ? index : nil
        return .routeSheet(HonorRouteLink(entry: entry, release: catalog.release, focus: focus))
    }
}
