import Foundation

public protocol WalkPhotoInterface: DataInterface {

    var localIdentifier: String { get }
    var capturedAt: Date { get }
    var capturedLat: Double { get }
    var capturedLng: Double { get }
    var keptAt: Date { get }

}

public extension WalkPhotoInterface {

    var localIdentifier: String { throwOnAccess() }
    var capturedAt: Date { throwOnAccess() }
    var capturedLat: Double { throwOnAccess() }
    var capturedLng: Double { throwOnAccess() }
    var keptAt: Date { throwOnAccess() }

}
