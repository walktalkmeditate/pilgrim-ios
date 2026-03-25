import ActivityKit
import Foundation

final class WalkActivityManager {

    static let shared = WalkActivityManager()
    private var currentActivity: Activity<WalkActivityAttributes>?
    private var lastDistanceUpdate: Double = 0
    private let distanceThreshold: Double = 15

    private init() {}

    func start(walkStartDate: Date, intention: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        end()

        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        let attributes = WalkActivityAttributes(
            walkStartDate: walkStartDate,
            intention: intention,
            isImperial: isImperial
        )
        let initialState = WalkActivityAttributes.ContentState(
            activeDurationSeconds: 0,
            distanceMeters: 0,
            isPaused: false,
            isMeditating: false,
            isRecordingVoice: false
        )

        do {
            currentActivity = try Activity<WalkActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )
            lastDistanceUpdate = 0
        } catch {
            print("[WalkActivity] Failed to start: \(error)")
        }
    }

    func update(
        activeDuration: TimeInterval,
        distanceMeters: Double,
        isPaused: Bool,
        isMeditating: Bool,
        isRecordingVoice: Bool
    ) {
        guard currentActivity != nil else { return }

        let distanceDelta = abs(distanceMeters - lastDistanceUpdate)
        let stateChanged = isPaused || isMeditating || isRecordingVoice
        guard distanceDelta >= distanceThreshold || stateChanged else { return }

        lastDistanceUpdate = distanceMeters

        let state = WalkActivityAttributes.ContentState(
            activeDurationSeconds: activeDuration,
            distanceMeters: distanceMeters,
            isPaused: isPaused,
            isMeditating: isMeditating,
            isRecordingVoice: isRecordingVoice
        )

        Task {
            await currentActivity?.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    func end() {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        Task {
            await activity.end(
                ActivityContent(
                    state: activity.content.state,
                    staleDate: nil
                ),
                dismissalPolicy: .default
            )
        }
    }
}
