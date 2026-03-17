import Foundation

public protocol WaypointInterface: DataInterface {

    var latitude: Double { get }
    var longitude: Double { get }
    var label: String { get }
    var icon: String { get }
    var timestamp: Date { get }

}

public extension WaypointInterface {

    var latitude: Double { throwOnAccess() }
    var longitude: Double { throwOnAccess() }
    var label: String { throwOnAccess() }
    var icon: String { throwOnAccess() }
    var timestamp: Date { throwOnAccess() }

}
