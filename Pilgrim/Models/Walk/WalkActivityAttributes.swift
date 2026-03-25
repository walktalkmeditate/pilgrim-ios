import ActivityKit
import Foundation

struct WalkActivityAttributes: ActivityAttributes {

    let walkStartDate: Date
    let intention: String?
    let isImperial: Bool

    struct ContentState: Codable, Hashable {
        var activeDurationSeconds: TimeInterval
        var distanceMeters: Double
        var isPaused: Bool
        var isMeditating: Bool
        var isRecordingVoice: Bool
    }
}
