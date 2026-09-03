import Foundation

/// Every Honor threshold in one place. Values from the spec; on-device
/// tuning candidates, not commitments.
enum HonorTuning {
    static let fixAccuracyMeters = 50.0
    static let onWayMeters = 60.0
    static let windowMeters = 300.0
    static let backwardTolerance = 0.02
    static let momentFracTolerance = 0.05
    static let reacquireSeconds: TimeInterval = 120
    static let reacquireRetrySeconds: TimeInterval = 10
    static let voiceRadiusMeters = 42.0
    static let momentRadiusMeters = 60.0
    static let voiceDropMeters = 300.0
    static let stationarySpeed = 0.4
    static let softTapMeters = 200.0
    static let softTapSeconds: TimeInterval = 120
    static let arrivalRadiusMeters = 30.0
    static let arrivalMinFrac = 0.9
    static let arrivalMinDistanceRatio = 0.5
    static let arrivalFixCount = SeekEngineTuning.arrivalFixCount
    static let arrivalAccuracyMeters = SeekEngineTuning.arrivalAccuracyMeters
}
