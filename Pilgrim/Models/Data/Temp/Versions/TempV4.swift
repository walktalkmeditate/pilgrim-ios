//
//  TempV4.swift
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

public enum TempV4 {
    
    public class Workout: Codable, TempValueConvertible {
        
        public var uuid: UUID?
        public var workoutType: Walk.WalkType
        public var distance: Double
        public var steps: Int?
        public var startDate: Date
        public var endDate: Date
        public var burnedEnergy: Double?
        public var isRace: Bool
        public var comment: String?
        public var isUserModified: Bool
        public var healthKitUUID: UUID?
        public var finishedRecording: Bool
        
        public var ascend: Double
        public var descend: Double
        public var activeDuration: Double
        public var pauseDuration: Double
        public var dayIdentifier: String
        public var talkDuration: Double
        public var meditateDuration: Double
        
        var _heartRates: [TempV4.WorkoutHeartRateDataSample]
        var _routeData: [TempV4.WorkoutRouteDataSample]
        var _pauses: [TempV4.WorkoutPause]
        var _workoutEvents: [TempV4.WorkoutEvent]
        var _voiceRecordings: [TempV4.VoiceRecording]
        var _activityIntervals: [TempV4.ActivityInterval]

        public var heartRates: [HeartRateDataSampleInterface] { _heartRates }
        public var routeData: [RouteDataSampleInterface] { _routeData }
        public var pauses: [WalkPauseInterface] { _pauses }
        public var workoutEvents: [WalkEventInterface] { _workoutEvents }
        public var voiceRecordings: [VoiceRecordingInterface] { _voiceRecordings }
        public var activityIntervals: [ActivityIntervalInterface] { _activityIntervals }
        public var events: [EventInterface] { throwOnAccess() }
        
        public init(uuid: UUID?, workoutType: Walk.WalkType, distance: Double, steps: Int?, startDate: Date, endDate: Date, burnedEnergy: Double?, isRace: Bool, comment: String?, isUserModified: Bool, healthKitUUID: UUID?, finishedRecording: Bool, ascend: Double, descend: Double, activeDuration: Double, pauseDuration: Double, dayIdentifier: String, talkDuration: Double = 0, meditateDuration: Double = 0, heartRates: [TempV4.WorkoutHeartRateDataSample], routeData: [TempV4.WorkoutRouteDataSample], pauses: [TempV4.WorkoutPause], workoutEvents: [TempV4.WorkoutEvent], voiceRecordings: [TempV4.VoiceRecording] = [], activityIntervals: [TempV4.ActivityInterval] = []) {
            self.uuid = uuid
            self.workoutType = workoutType
            self.distance = distance
            self.steps = steps
            self.startDate = startDate
            self.endDate = endDate
            self.burnedEnergy = burnedEnergy
            self.isRace = isRace
            self.comment = comment
            self.isUserModified = isUserModified
            self.healthKitUUID = healthKitUUID
            self.finishedRecording = finishedRecording
            self.ascend = ascend
            self.descend = descend
            self.activeDuration = activeDuration
            self.pauseDuration = pauseDuration
            self.dayIdentifier = dayIdentifier
            self.talkDuration = talkDuration
            self.meditateDuration = meditateDuration
            self._heartRates = heartRates
            self._routeData = routeData
            self._pauses = pauses
            self._workoutEvents = workoutEvents
            self._voiceRecordings = voiceRecordings
            self._activityIntervals = activityIntervals
        }
        
        public var asTemp: TempWalk {
            return self
        }
    }

    public class WorkoutPause: Codable, TempValueConvertible {
        
        public var uuid: UUID?
        public var startDate: Date
        public var endDate: Date
        public var pauseType: WalkPause.PauseType

        public init(uuid: UUID?, startDate: Date, endDate: Date, pauseType: WalkPause.PauseType) {
            self.uuid = uuid
            self.startDate = startDate
            self.endDate = endDate
            self.pauseType = pauseType
        }
        
        public var asTemp: TempWalkPause {
            return self
        }
    }

    public class WorkoutEvent: Codable, TempValueConvertible {
        
        public var uuid: UUID?
        public var eventType: WalkEvent.EventType
        public var timestamp: Date

        public init(uuid: UUID?, eventType: WalkEvent.EventType, timestamp: Date) {
            self.uuid = uuid
            self.eventType = eventType
            self.timestamp = timestamp
        }
        
        public var asTemp: TempWalkEvent {
            return self
        }
    }
    
    public class WorkoutRouteDataSample: Codable, TempValueConvertible {
        
        public var uuid: UUID?
        public var timestamp: Date
        public var latitude: Double
        public var longitude: Double
        public var altitude: Double
        public var horizontalAccuracy: Double
        public var verticalAccuracy: Double
        public var speed: Double
        public var direction: Double

        public init(uuid: UUID?, timestamp: Date, latitude: Double, longitude: Double, altitude: Double, horizontalAccuracy: Double, verticalAccuracy: Double, speed: Double, direction: Double) {
            self.uuid = uuid
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.speed = speed
            self.direction = direction
        }
        
        public var asTemp: TempRouteDataSample {
            return self
        }
    }
    
    public class WorkoutHeartRateDataSample: Codable, TempValueConvertible {
        
        public var uuid: UUID?
        public var heartRate: Int
        public var timestamp: Date

        public init(uuid: UUID?, heartRate: Int, timestamp: Date) {
            self.uuid = uuid
            self.heartRate = heartRate
            self.timestamp = timestamp
        }
        
        public var asTemp: TempHeartRateDataSample {
            return self
        }
    }
    
    public class VoiceRecording: Codable, TempValueConvertible {

        public var uuid: UUID?
        public var startDate: Date
        public var endDate: Date
        public var duration: Double
        public var fileRelativePath: String
        public var transcription: String?

        public init(uuid: UUID?, startDate: Date, endDate: Date, duration: Double, fileRelativePath: String, transcription: String? = nil) {
            self.uuid = uuid
            self.startDate = startDate
            self.endDate = endDate
            self.duration = duration
            self.fileRelativePath = fileRelativePath
            self.transcription = transcription
        }

        public var asTemp: TempVoiceRecording {
            return self
        }
    }

    public class ActivityInterval: Codable, TempValueConvertible {

        public var uuid: UUID?
        public var activityType: PilgrimV2.ActivityInterval.ActivityType
        public var startDate: Date
        public var endDate: Date

        public init(uuid: UUID?, activityType: PilgrimV2.ActivityInterval.ActivityType, startDate: Date, endDate: Date) {
            self.uuid = uuid
            self.activityType = activityType
            self.startDate = startDate
            self.endDate = endDate
        }

        public var asTemp: TempActivityInterval {
            return self
        }
    }

    public class Event: Codable, TempValueConvertible {

        public var uuid: UUID?
        public var title: String
        public var comment: String?
        public var startDate: Date?
        public var endDate: Date?
        public var workouts: [UUID]

        public init(uuid: UUID?, title: String, comment: String?, startDate: Date?, endDate: Date?, workouts: [UUID]) {
            self.uuid = uuid
            self.title = title
            self.comment = comment
            self.startDate = startDate
            self.endDate = endDate
            self.workouts = workouts
        }
        
        public var asTemp: TempEvent {
            return self
        }
    }
    
}
