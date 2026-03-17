import Foundation
import CoreStore

public typealias Waypoint = PilgrimV6.Waypoint

extension Waypoint: WaypointInterface {

    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var latitude: Double { threadSafeSyncReturn { self._latitude.value } }
    public var longitude: Double { threadSafeSyncReturn { self._longitude.value } }
    public var label: String { threadSafeSyncReturn { self._label.value } }
    public var icon: String { threadSafeSyncReturn { self._icon.value } }
    public var timestamp: Date { threadSafeSyncReturn { self._timestamp.value } }
    public var workout: WalkInterface? { self._workout.value as? WalkInterface }

}

extension Waypoint: TempValueConvertible {

    public var asTemp: TempWaypoint {
        TempWaypoint(
            uuid: uuid,
            latitude: latitude,
            longitude: longitude,
            label: label,
            icon: icon,
            timestamp: timestamp
        )
    }

}
