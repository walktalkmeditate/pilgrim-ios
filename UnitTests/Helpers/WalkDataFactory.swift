import Foundation
@testable import Pilgrim

enum WalkDataFactory {

    static func makeWalk(
        uuid: UUID? = nil,
        workoutType: Walk.WalkType = .walking,
        distance: Double = 1000,
        steps: Int? = nil,
        startDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        endDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 30, 0),
        burnedEnergy: Double? = nil,
        isRace: Bool = false,
        comment: String? = nil,
        isUserModified: Bool = false,
        healthKitUUID: UUID? = nil,
        finishedRecording: Bool = true,
        ascend: Double = 0,
        descend: Double = 0,
        activeDuration: Double = 1800,
        pauseDuration: Double = 0,
        dayIdentifier: String = "20240615",
        talkDuration: Double = 0,
        meditateDuration: Double = 0,
        heartRates: [TempV4.WorkoutHeartRateDataSample] = [],
        routeData: [TempV4.WorkoutRouteDataSample] = [],
        pauses: [TempV4.WorkoutPause] = [],
        workoutEvents: [TempV4.WorkoutEvent] = [],
        voiceRecordings: [TempV4.VoiceRecording] = [],
        activityIntervals: [TempV4.ActivityInterval] = [],
        favicon: String? = nil
    ) -> TempWalk {
        TempWalk(
            uuid: uuid, workoutType: workoutType, distance: distance, steps: steps,
            startDate: startDate, endDate: endDate, burnedEnergy: burnedEnergy,
            isRace: isRace, comment: comment, isUserModified: isUserModified,
            healthKitUUID: healthKitUUID, finishedRecording: finishedRecording,
            ascend: ascend, descend: descend, activeDuration: activeDuration,
            pauseDuration: pauseDuration, dayIdentifier: dayIdentifier,
            talkDuration: talkDuration, meditateDuration: meditateDuration,
            heartRates: heartRates, routeData: routeData, pauses: pauses,
            workoutEvents: workoutEvents, voiceRecordings: voiceRecordings,
            activityIntervals: activityIntervals,
            favicon: favicon
        )
    }

    static func makePause(
        uuid: UUID? = nil,
        startDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 10, 0),
        endDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 15, 0),
        pauseType: WalkPause.PauseType = .manual
    ) -> TempWalkPause {
        TempWalkPause(uuid: uuid, startDate: startDate, endDate: endDate, pauseType: pauseType)
    }

    static func makeRouteDataSample(
        uuid: UUID? = nil,
        timestamp: Date = DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
        latitude: Double = 48.8566,
        longitude: Double = 2.3522,
        altitude: Double = 35,
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = 3,
        speed: Double = 1.4,
        direction: Double = 0
    ) -> TempRouteDataSample {
        TempRouteDataSample(
            uuid: uuid, timestamp: timestamp, latitude: latitude, longitude: longitude,
            altitude: altitude, horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy, speed: speed, direction: direction
        )
    }

    static func makeVoiceRecording(
        uuid: UUID? = nil,
        startDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 5, 0),
        endDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 6, 0),
        duration: Double = 60,
        fileRelativePath: String = "recordings/test.m4a",
        transcription: String? = "Test transcription"
    ) -> TempVoiceRecording {
        TempVoiceRecording(
            uuid: uuid, startDate: startDate, endDate: endDate,
            duration: duration, fileRelativePath: fileRelativePath,
            transcription: transcription
        )
    }

    static func makeActivityInterval(
        uuid: UUID? = nil,
        activityType: ActivityInterval.ActivityType = .meditation,
        startDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 10, 0),
        endDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 15, 0)
    ) -> TempActivityInterval {
        TempActivityInterval(uuid: uuid, activityType: activityType, startDate: startDate, endDate: endDate)
    }

    static func makeWorkoutEvent(
        uuid: UUID? = nil,
        eventType: WalkEvent.EventType = .marker,
        timestamp: Date = DateFactory.makeDate(2024, 6, 15, 9, 10, 0)
    ) -> TempWalkEvent {
        TempWalkEvent(uuid: uuid, eventType: eventType, timestamp: timestamp)
    }
}
