import Foundation

/// The persistence vocabulary for honor walks, shaped like SeekPersistence:
/// a `.honorMode` event at recording start, and on reaching the end of the
/// Way a `.honorArrival` event plus a waypoint with the reserved icon.
enum HonorPersistence {

    /// Must never collide with WaypointMarkingSheet's presets, "mappin", or
    /// SeekPersistence.arrivalWaypointIcon.
    static let arrivalWaypointIcon = "signpost.right.fill"

    static func isArrivalWaypoint(_ waypoint: WaypointInterface) -> Bool {
        waypoint.icon == arrivalWaypointIcon
    }

    static func arrivalWaypointLabel(wayTitle: String) -> String {
        String(format: arrivalLabelFormat, wayTitle)
    }

    static let honorModeEventName = NSLocalizedString(
        "honor.event.honor_mode", value: "Honor",
        comment: "Name of the walk event marking a walk as an honor walk.")

    static let honorArrivalEventName = NSLocalizedString(
        "honor.event.arrival", value: "Way walked",
        comment: "Name of the walk event written when the end of a Way is reached.")

    private static let arrivalLabelFormat = NSLocalizedString(
        "honor.arrival.label", value: "Walked their way: %@",
        comment: "Waypoint label at the end of an honored Way; %@ is the Way's title.")
}
