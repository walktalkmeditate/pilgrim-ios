//
//  Walk.swift
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
import CoreStore

public typealias Walk = PilgrimV5.Workout

extension PilgrimV2.Workout {

    public enum WalkType: CaseIterable, CustomStringConvertible, CustomDebugStringConvertible, RawRepresentable, ImportableAttributeType, Codable {

        case walking, unknown

        public init(rawValue: Int) {
            switch rawValue {
            case 1:
                self = .walking
            default:
                self = .unknown
            }
        }

        public var rawValue: Int {
            switch self {
            case .walking:
                return 1
            case .unknown:
                return -1
            }
        }

        public var description: String {
            switch self {
            case .walking:
                return "Walk"
            case .unknown:
                return "Unknown"
            }
        }

        public var debugDescription: String {
            switch self {
            case .walking:
                return "Walking"
            case .unknown:
                return "Unknown"
            }
        }

        public var METSpeedMultiplier: Double {
            switch self {
            case .walking:
                return 0.655
            case .unknown:
                return 0
            }
        }

    }

}

public extension Walk {

    var hasRouteData: Bool {
        return !self.routeData.isEmpty
    }

    typealias WalkType = PilgrimV2.Workout.WalkType

}

// MARK: - CustomStringConvertible

extension Walk: CustomStringConvertible {
    
    public var description: String {
        
        var desc = "Walk("
        
        if let uuid = uuid {
            desc += "uuid: \(uuid), "
        }
        
        desc += "type: \(workoutType.debugDescription), start: \(startDate), end: \(endDate), distance: \(distance) m, activeDuration: \(activeDuration) s, pauseDuration: \(pauseDuration) s, pauses: \(pauses.count), events: \(events.count), heartRates: \(heartRates.count)"
        
        if let energy = burnedEnergy {
            desc += " burnedEnergy: \(energy) kcal"
        }
        
        return desc + ")"
    }
}

// MARK: - WalkInterface

extension Walk: WalkInterface {
    
    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var workoutType: Walk.WalkType { threadSafeSyncReturn { self._workoutType.value } }
    public var distance: Double { threadSafeSyncReturn { self._distance.value } }
    public var steps: Int? { threadSafeSyncReturn { self._steps.value } }
    public var startDate: Date { threadSafeSyncReturn { self._startDate.value } }
    public var endDate: Date { threadSafeSyncReturn { self._endDate.value } }
    public var burnedEnergy: Double? { threadSafeSyncReturn { self._burnedEnergy.value } }
    public var isRace: Bool { threadSafeSyncReturn { self._isRace.value } }
    public var comment: String? { threadSafeSyncReturn { self._comment.value } }
    public var isUserModified: Bool { threadSafeSyncReturn { self._isUserModified.value } }
    public var healthKitUUID: UUID? { threadSafeSyncReturn { self._healthKitUUID.value } }
    public var finishedRecording: Bool { threadSafeSyncReturn { self._finishedRecording.value } }
    public var ascend: Double { threadSafeSyncReturn { self._ascend.value } }
    public var descend: Double { threadSafeSyncReturn { self._descend.value } }
    public var activeDuration: Double { threadSafeSyncReturn { self._activeDuration.value } }
    public var pauseDuration: Double { threadSafeSyncReturn { self._pauseDuration.value } }
    public var dayIdentifier: String { threadSafeSyncReturn { self._dayIdentifier.value } }
    public var talkDuration: Double { threadSafeSyncReturn { self._talkDuration.value } }
    public var meditateDuration: Double { threadSafeSyncReturn { self._meditateDuration.value } }
    public var routeData: [RouteDataSampleInterface] { threadSafeSyncReturn { self._routeData.value } }
    public var pauses: [WalkPauseInterface] { threadSafeSyncReturn { self._pauses.value } }
    public var workoutEvents: [WalkEventInterface] { threadSafeSyncReturn { self._workoutEvents.value } }
    public var events: [EventInterface] { threadSafeSyncReturn { Array(self._events.value) } }
    public var voiceRecordings: [VoiceRecordingInterface] { threadSafeSyncReturn { self._voiceRecordings.value } }
    public var heartRates: [HeartRateDataSampleInterface] { threadSafeSyncReturn { self._heartRates.value } }
    public var activityIntervals: [ActivityIntervalInterface] { threadSafeSyncReturn { self._activityIntervals.value } }
    public var favicon: String? { threadSafeSyncReturn { self._favicon.value } }

}

// MARK: - TempValueConvertible

extension Walk: TempValueConvertible {
    
    public var asTemp: TempWalk {
        return threadSafeSyncReturn {
            TempWalk(
                uuid: self._uuid.value,
                workoutType: self._workoutType.value,
                distance: self._distance.value,
                steps: self._steps.value,
                startDate: self._startDate.value,
                endDate: self._endDate.value,
                burnedEnergy: self._burnedEnergy.value,
                isRace: self._isRace.value,
                comment: self._comment.value,
                isUserModified: self._isUserModified.value,
                healthKitUUID: self._healthKitUUID.value,
                finishedRecording: self._finishedRecording.value,
                ascend: self._ascend.value,
                descend: self._descend.value,
                activeDuration: self._activeDuration.value,
                pauseDuration: self._pauseDuration.value,
                dayIdentifier: self._dayIdentifier.value,
                talkDuration: self._talkDuration.value,
                meditateDuration: self._meditateDuration.value,
                heartRates: self._heartRates.value.map { $0.asTemp },
                routeData: self._routeData.value.map { $0.asTemp },
                pauses: self._pauses.value.map { $0.asTemp },
                workoutEvents: self._workoutEvents.value.map { $0.asTemp },
                voiceRecordings: self._voiceRecordings.value.map { $0.asTemp },
                activityIntervals: self._activityIntervals.value.map { $0.asTemp },
                favicon: self._favicon.value
            )
        }
    }

}
