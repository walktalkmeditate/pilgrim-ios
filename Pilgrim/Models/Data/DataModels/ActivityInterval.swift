import Foundation
import CoreStore

public typealias ActivityInterval = PilgrimV5.ActivityInterval

extension PilgrimV2.ActivityInterval {

    public enum ActivityType: RawRepresentable, ImportableAttributeType, Codable {

        case unknown
        case meditation

        public init(rawValue: Int) {
            switch rawValue {
            case 1:
                self = .meditation
            default:
                self = .unknown
            }
        }

        public var rawValue: Int {
            switch self {
            case .unknown:
                return 0
            case .meditation:
                return 1
            }
        }
    }

}

public extension ActivityInterval {

    typealias ActivityType = PilgrimV2.ActivityInterval.ActivityType

}

// MARK: - ActivityIntervalInterface

extension ActivityInterval: ActivityIntervalInterface {

    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var activityType: ActivityType { threadSafeSyncReturn { self._activityType.value } }
    public var startDate: Date { threadSafeSyncReturn { self._startDate.value } }
    public var endDate: Date { threadSafeSyncReturn { self._endDate.value } }
    public var workout: WalkInterface? { self._workout.value }

}

// MARK: - TempValueConvertible

extension ActivityInterval: TempValueConvertible {

    public var asTemp: TempActivityInterval {
        TempActivityInterval(
            uuid: uuid,
            activityType: activityType,
            startDate: startDate,
            endDate: endDate
        )
    }

}
