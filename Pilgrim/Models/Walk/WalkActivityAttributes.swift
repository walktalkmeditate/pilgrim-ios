import ActivityKit
import Foundation

struct WalkActivityAttributes: ActivityAttributes {

    let walkStartDate: Date
    let intention: String?
    let isImperial: Bool

    struct ContentState: Codable, Hashable {
        var activeDurationSeconds: TimeInterval
        var walkTimerStart: Date?
        var distanceMeters: Double
        var meditationTimerStart: Date?
        var talkTimerStart: Date?
        var isPaused: Bool
        var isMeditating: Bool
        var isRecordingVoice: Bool
    }
}
