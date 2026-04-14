import Foundation

extension TempV4 {
    public class WalkPhoto: Codable, TempValueConvertible {
        public var uuid: UUID?
        public var localIdentifier: String
        public var capturedAt: Date
        public var capturedLat: Double
        public var capturedLng: Double
        public var keptAt: Date

        public init(uuid: UUID?, localIdentifier: String, capturedAt: Date, capturedLat: Double, capturedLng: Double, keptAt: Date) {
            self.uuid = uuid
            self.localIdentifier = localIdentifier
            self.capturedAt = capturedAt
            self.capturedLat = capturedLat
            self.capturedLng = capturedLng
            self.keptAt = keptAt
        }

        public var asTemp: TempWalkPhoto { return self }
    }
}

extension TempV4.WalkPhoto: WalkPhotoInterface {}
