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
        /// nil for wander walks — the payload and rendering stay identical
        /// to pre-seek builds (parity requirement; synthesized Codable
        /// omits the key when nil).
        var seek: SeekGlanceState?
    }
}
