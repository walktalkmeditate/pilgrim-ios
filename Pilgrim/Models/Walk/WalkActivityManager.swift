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
        currentActivity = nil

        // Enumerate iOS's authoritative list of activities, not just the
        // one we remember. On a normal walk-end the tracked activity is
        // one of them and gets the frozen final state. If the app crashed
        // or was force-quit mid-walk, iOS may still be showing an orphan
        // activity that our in-memory manager has no reference to. Ending
        // all of them guarantees the lock screen is clean.
        let activities = Activity<WalkActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        Task {
            for activity in activities {
                // Freeze timer starts + transient flags so the final
                // frame the user sees (before dismissal) reads as
                // "finished" rather than "still counting up."
                let frozenState = WalkActivityAttributes.ContentState(
                    activeDurationSeconds: activity.content.state.activeDurationSeconds,
                    walkTimerStart: nil,
                    distanceMeters: activity.content.state.distanceMeters,
                    meditationTimerStart: nil,
                    talkTimerStart: nil,
                    isPaused: false,
                    isMeditating: false,
                    isRecordingVoice: false
                )
                await activity.end(
                    ActivityContent(state: frozenState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    /// Ends every Live Activity of this type, regardless of whether the
    /// manager tracks it. Call on app launch to clean up orphans left
    /// behind by a crash, force-quit, or OOM kill — any activity still
    /// alive at launch time is necessarily stale because the session that
    /// created it is no longer running. Safe to call when no activities
    /// exist (no-op).
    func endAllStaleActivities() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<WalkActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        print("[WalkActivity] Cleaning up \(activities.count) stale activity(ies) at launch")
        currentActivity = nil

        Task {
            for activity in activities {
                await activity.end(
                    ActivityContent(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
