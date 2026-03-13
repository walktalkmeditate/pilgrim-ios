//
//  Temp.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import CoreLocation

public typealias TempWalk = TempV4.Workout
extension TempWalk: WalkInterface, Identifiable {
    public var id: UUID { uuid ?? UUID() }


    convenience init(from object: WalkInterface) {

        self.init(
            uuid: object.uuid,
            workoutType: object.workoutType,
            distance: object.distance,
            steps: object.steps,
            startDate: object.startDate,
            endDate: object.endDate,
            burnedEnergy: object.burnedEnergy,
            isRace: object.isRace,
            comment: object.comment,
            isUserModified: object.isUserModified,
            healthKitUUID: object.healthKitUUID,
            finishedRecording: object.finishedRecording,
            ascend: object.ascend,
            descend: object.descend,
            activeDuration: object.activeDuration,
            pauseDuration: object.pauseDuration,
            dayIdentifier: object.dayIdentifier,
            talkDuration: object.talkDuration,
            meditateDuration: object.meditateDuration,
            heartRates: object.heartRates.map { .init(from: $0) },
            routeData: object.routeData.map { .init(from: $0) },
            pauses: object.pauses.map { .init(from: $0) },
            workoutEvents: object.workoutEvents.map { .init(from: $0) },
            voiceRecordings: object.voiceRecordings.map { .init(from: $0) },
            activityIntervals: object.activityIntervals.map { .init(from: $0) }
        )
    }
}

public typealias TempWalkPause = TempV4.WorkoutPause
extension TempWalkPause: WalkPauseInterface {
    
    convenience init(from object: WalkPauseInterface) {
        
        self.init(
            uuid: object.uuid,
            startDate: object.startDate,
            endDate: object.endDate,
            pauseType: object.pauseType
        )
    }
    
    /**
     Combining two instances of the TempWalkPause object into one.
     - parameter with: the `TempWalkPause` object to merge
     - returns: one `TempWalkPause` instance with the earliest start date and the latest end date of the provided and `self`
    */
    func merge(with anotherPause: TempWalkPause) -> TempWalkPause {
        
        let commonStart = startDate < anotherPause.startDate ? startDate : anotherPause.startDate
        let commonEnd = endDate > anotherPause.endDate ? endDate : anotherPause.endDate
        
        return TempWalkPause(
            uuid: nil,
            startDate: commonStart,
            endDate: commonEnd,
            pauseType: [pauseType, anotherPause.pauseType].contains(.manual) ? .manual : .automatic
        )
    }
}

public typealias TempWalkEvent = TempV4.WorkoutEvent
extension TempWalkEvent: WalkEventInterface {
    
    convenience init(from object: WalkEventInterface) {
        
        self.init(
            uuid: object.uuid,
            eventType: object.eventType,
            timestamp: object.timestamp
        )
    }
}

public typealias TempRouteDataSample = TempV4.WorkoutRouteDataSample
extension TempRouteDataSample: RouteDataSampleInterface {
    
    convenience init(from object: RouteDataSampleInterface) {
        
        self.init(
            uuid: object.uuid,
            timestamp: object.timestamp,
            latitude: object.latitude,
            longitude: object.longitude,
            altitude: object.altitude,
            horizontalAccuracy: object.horizontalAccuracy,
            verticalAccuracy: object.verticalAccuracy,
            speed: object.speed,
            direction: object.direction
        )
    }
    
}

public typealias TempHeartRateDataSample = TempV4.WorkoutHeartRateDataSample
extension TempHeartRateDataSample: HeartRateDataSampleInterface {
    
    convenience init(from object: HeartRateDataSampleInterface) {
        
        self.init(
            uuid: object.uuid,
            heartRate: object.heartRate,
            timestamp: object.timestamp
        )
        
    }
    
}

public typealias TempActivityInterval = TempV4.ActivityInterval
extension TempActivityInterval: ActivityIntervalInterface {

    convenience init(from object: ActivityIntervalInterface) {
        self.init(
            uuid: object.uuid,
            activityType: object.activityType,
            startDate: object.startDate,
            endDate: object.endDate
        )
    }
}

public typealias TempVoiceRecording = TempV4.VoiceRecording
extension TempVoiceRecording: VoiceRecordingInterface {

    convenience init(from object: VoiceRecordingInterface) {
        self.init(
            uuid: object.uuid,
            startDate: object.startDate,
            endDate: object.endDate,
            duration: object.duration,
            fileRelativePath: object.fileRelativePath,
            transcription: object.transcription,
            wordsPerMinute: object.wordsPerMinute
        )
    }
}

public typealias TempEvent = TempV4.Event
extension TempEvent: EventInterface {
    
    convenience init(from object: EventInterface) {
        
        self.init(
            uuid: object.uuid,
            title: object.title,
            comment: object.comment,
            startDate: object.startDate,
            endDate: object.endDate,
            workouts: object.workouts.compactMap { $0.uuid }
        )
    }
    
}
