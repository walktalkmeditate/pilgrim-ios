import Foundation

extension TempV4 {
    public class Waypoint: Codable, TempValueConvertible {
        public var uuid: UUID?
        public var latitude: Double
        public var longitude: Double
        public var label: String
        public var icon: String
        public var timestamp: Date

        public init(uuid: UUID?, latitude: Double, longitude: Double, label: String, icon: String, timestamp: Date) {
            self.uuid = uuid
            self.latitude = latitude
            self.longitude = longitude
            self.label = label
            self.icon = icon
            self.timestamp = timestamp
        }

        public var asTemp: TempWaypoint { return self }
    }
}

extension TempV4.Waypoint: WaypointInterface {}
