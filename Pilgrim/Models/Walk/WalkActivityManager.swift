import ActivityKit
import Foundation

final class WalkActivityManager {

    static let shared = WalkActivityManager()
    private var currentActivity: Activity<WalkActivityAttributes>?
    private var lastDistanceUpdate: Double = 0
    private var lastUpdateDate: Date = .distantPast
    private var lastIsPaused = false
    private var lastIsMeditating = false
    private var lastIsRecordingVoice = false
    private let distanceThreshold: Double = 15
    private let timeThreshold: TimeInterval = 15

    private init() {}

    func start(walkStartDate: Date, intention: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
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
            walkTimerStart: walkStartDate,
            distanceMeters: 0,
            meditationTimerStart: nil,
            talkTimerStart: nil,
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
            lastUpdateDate = Date()
            lastIsPaused = false
            lastIsMeditating = false
            lastIsRecordingVoice = false
        } catch {
            print("[WalkActivity] Failed to start: \(error)")
        }
    }

    func update(
        activeDuration: TimeInterval,
        walkTimerStart: Date?,
        distanceMeters: Double,
        meditationTimerStart: Date?,
        talkTimerStart: Date?,
        isPaused: Bool,
        isMeditating: Bool,
        isRecordingVoice: Bool
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard currentActivity != nil else { return }

        let distanceDelta = abs(distanceMeters - lastDistanceUpdate)
        let stateChanged = isPaused != lastIsPaused
            || isMeditating != lastIsMeditating
            || isRecordingVoice != lastIsRecordingVoice
        let timeElapsed = Date().timeIntervalSince(lastUpdateDate) >= timeThreshold

        guard distanceDelta >= distanceThreshold || stateChanged || timeElapsed else { return }

        lastDistanceUpdate = distanceMeters
        lastUpdateDate = Date()
        lastIsPaused = isPaused
        lastIsMeditating = isMeditating
        lastIsRecordingVoice = isRecordingVoice

        let state = WalkActivityAttributes.ContentState(
            activeDurationSeconds: activeDuration,
            walkTimerStart: walkTimerStart,
            distanceMeters: distanceMeters,
            meditationTimerStart: meditationTimerStart,
            talkTimerStart: talkTimerStart,
            isPaused: isPaused,
            isMeditating: isMeditating,
            isRecordingVoice: isRecordingVoice
        )

        let staleDate = Date().addingTimeInterval(timeThreshold * 3)

        Task {
            await currentActivity?.update(
                ActivityContent(state: state, staleDate: staleDate)
            )
        }
    }

    func end() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let activity = currentActivity else { return }
        currentActivity = nil

        let finalState = WalkActivityAttributes.ContentState(
            activeDurationSeconds: activity.content.state.activeDurationSeconds,
            walkTimerStart: nil,
            distanceMeters: activity.content.state.distanceMeters,
            meditationTimerStart: nil,
            talkTimerStart: nil,
            isPaused: false,
            isMeditating: false,
            isRecordingVoice: false
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}
