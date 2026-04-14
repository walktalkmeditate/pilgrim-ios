import Foundation
import CoreStore

public typealias WalkPhoto = PilgrimV7.WalkPhoto

extension WalkPhoto: WalkPhotoInterface {

    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var localIdentifier: String { threadSafeSyncReturn { self._localIdentifier.value } }
    public var capturedAt: Date { threadSafeSyncReturn { self._capturedAt.value } }
    public var capturedLat: Double { threadSafeSyncReturn { self._capturedLat.value } }
    public var capturedLng: Double { threadSafeSyncReturn { self._capturedLng.value } }
    public var keptAt: Date { threadSafeSyncReturn { self._keptAt.value } }
    public var workout: WalkInterface? { self._workout.value as? WalkInterface }

}

extension WalkPhoto: TempValueConvertible {

    public var asTemp: TempWalkPhoto {
        TempWalkPhoto(
            uuid: uuid,
            localIdentifier: localIdentifier,
            capturedAt: capturedAt,
            capturedLat: capturedLat,
            capturedLng: capturedLng,
            keptAt: keptAt
        )
    }

}
