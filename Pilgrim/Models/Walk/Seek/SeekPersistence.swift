import Foundation

/// The persistence vocabulary for seek walks. A seek is marked by a
/// `.seekMode` walk event written once at recording start; each reached
/// clearing writes a `.seekArrival` event plus a waypoint carrying the
/// reserved icon, so map rendering, summary grouping, and `.pilgrim`
/// round-trips reuse the existing waypoint machinery unchanged.
enum SeekPersistence {

    /// Reserved SF symbol for arrival waypoints. Must never collide with the
    /// user-pickable icons in `WaypointMarkingSheet` (presets plus the
    /// custom-note "mappin") — summary grouping tells arrivals apart by
    /// exactly this icon string.
    static let arrivalWaypointIcon = "sun.haze"

    static func isArrivalWaypoint(_ waypoint: WaypointInterface) -> Bool {
        waypoint.icon == arrivalWaypointIcon
    }

    /// Label for the arrival waypoint of a clearing, by 1-based ordinal.
    static func arrivalWaypointLabel(clearingOrdinal ordinal: Int) -> String {
        switch ordinal {
        case 1: return firstClearingLabel
        case 2: return secondClearingLabel
        case 3: return thirdClearingLabel
        default: return String(format: nthClearingLabelFormat, ordinal)
        }
    }

    // MARK: - Localized Strings

    static let seekModeEventName = NSLocalizedString(
        "seek.event.seek_mode",
        value: "Seek",
        comment: "Name of the walk event marking a walk as a seek."
    )

    static let seekArrivalEventName = NSLocalizedString(
        "seek.event.arrival",
        value: "Clearing reached",
        comment: "Name of the walk event written when a seek clearing is reached."
    )

    private static let firstClearingLabel = NSLocalizedString(
        "seek.arrival.label.first",
        value: "First clearing",
        comment: "Waypoint label for the first clearing reached during a seek."
    )

    private static let secondClearingLabel = NSLocalizedString(
        "seek.arrival.label.second",
        value: "Second clearing",
        comment: "Waypoint label for the second clearing reached during a seek."
    )

    private static let thirdClearingLabel = NSLocalizedString(
        "seek.arrival.label.third",
        value: "Third clearing",
        comment: "Waypoint label for the third clearing reached during a seek."
    )

    private static let nthClearingLabelFormat = NSLocalizedString(
        "seek.arrival.label.nth",
        value: "Clearing %d",
        comment: "Fallback waypoint label for a reached seek clearing beyond the third; %d is the clearing number."
    )
}
