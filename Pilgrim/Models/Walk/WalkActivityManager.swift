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
    private var lastSeekGlance: SeekGlanceState?
    static let distanceThreshold: Double = 15
    static let timeThreshold: TimeInterval = 15
    /// Seek updates arrive on ~100 m bucket changes, so the dead-process
    /// net must outlive the longest plausible gap between buckets (~3 min
    /// at a slow walk) — the wander 45 s net would mark live seeks stale.
    static let seekStaleInterval: TimeInterval = 180

    private init() {}

    /// Pure gating decision: push on meaningful movement, a flag flip, a
    /// changed seek glance (bucket/hint/completion — naturally coarse), or
    /// the periodic floor as fallback.
    static func shouldPush(
        movedMeters: Double,
        flagsChanged: Bool,
        seekGlanceChanged: Bool,
        secondsSinceLastPush: TimeInterval
    ) -> Bool {
        movedMeters >= distanceThreshold
            || flagsChanged
            || seekGlanceChanged
            || secondsSinceLastPush >= timeThreshold
    }

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
            lastSeekGlance = nil
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
        isRecordingVoice: Bool,
        seek: SeekGlanceState? = nil
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let activity = currentActivity else { return }

        let stateChanged = isPaused != lastIsPaused
            || isMeditating != lastIsMeditating
            || isRecordingVoice != lastIsRecordingVoice

        guard Self.shouldPush(
            movedMeters: abs(distanceMeters - lastDistanceUpdate),
            flagsChanged: stateChanged,
            seekGlanceChanged: seek != lastSeekGlance,
            secondsSinceLastPush: Date().timeIntervalSince(lastUpdateDate)
        ) else { return }

        lastDistanceUpdate = distanceMeters
        lastUpdateDate = Date()
        lastIsPaused = isPaused
        lastIsMeditating = isMeditating
        lastIsRecordingVoice = isRecordingVoice
        lastSeekGlance = seek

        let state = WalkActivityAttributes.ContentState(
            activeDurationSeconds: activeDuration,
            walkTimerStart: walkTimerStart,
            distanceMeters: distanceMeters,
            meditationTimerStart: meditationTimerStart,
            talkTimerStart: talkTimerStart,
            isPaused: isPaused,
            isMeditating: isMeditating,
            isRecordingVoice: isRecordingVoice,
            seek: seek
        )

        let staleInterval = seek != nil ? Self.seekStaleInterval : Self.timeThreshold * 3
        let staleDate = Date().addingTimeInterval(staleInterval)

        Task {
            await activity.update(
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

        let suffix = activities.count == 1 ? "activity" : "activities"
        print("[WalkActivity] Cleaning up \(activities.count) stale \(suffix) at launch")
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
