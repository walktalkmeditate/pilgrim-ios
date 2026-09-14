import Foundation

/// The persistence vocabulary for honor walks, shaped like SeekPersistence:
/// a `.honorMode` event at recording start, and on reaching the end of the
/// Way a `.honorArrival` event plus a waypoint with the reserved icon.
enum HonorPersistence {

    /// Must never collide with WaypointMarkingSheet's presets, "mappin", or
    /// SeekPersistence.arrivalWaypointIcon.
    static let arrivalWaypointIcon = "signpost.right.fill"

    /// Replies are keyed by the `n` in a `voice-n` id. A stage has no
    /// voices, so its arrival reflection is filed under a reserved index no
    /// `voice-n` can ever produce.
    static let stageReflectionOrigin = -1
    static let stageReflectionMomentID = "stage-reflection"

    /// The moment the reply path records against: not a moment of the Way,
    /// but the stage's end place wearing a moment's shape so `replyHere`,
    /// `originIndex(of:)`, and `existingReplyURL(for:)` all work unchanged.
    static func stageReflectionMoment(for stage: WayStage) -> WayMoment {
        WayMoment(id: stageReflectionMomentID, frac: 1, at: stage.end.at,
                  kind: .waypoint(label: stage.end.name, icon: arrivalWaypointIcon))
    }

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
