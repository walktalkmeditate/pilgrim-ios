//
//  NewWalk.swift
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

class NewWalk: TempWalk {
    
    init(workoutType: Walk.WalkType, distance: Double, steps: Int?, startDate: Date, endDate: Date, isRace: Bool, comment: String?, isUserModified: Bool, finishedRecording: Bool, heartRates: [TempV4.WorkoutHeartRateDataSample], routeData: [TempV4.WorkoutRouteDataSample], pauses: [TempV4.WorkoutPause], workoutEvents: [TempV4.WorkoutEvent], voiceRecordings: [TempV4.VoiceRecording] = [], activityIntervals: [TempV4.ActivityInterval] = [], waypoints: [TempV4.Waypoint] = [], weatherCondition: String? = nil, weatherTemperature: Double? = nil, weatherHumidity: Double? = nil, weatherWindSpeed: Double? = nil) {

        let bodyWeight: Double? = UserPreferences.weight.value
        let burnedEnergy: Double? = bodyWeight != nil ? Computation.calculateBurnedEnergy(for: workoutType, distance: distance, weight: bodyWeight!) : nil

        let altitudes = routeData.map { $0.altitude }
        let elevation = Computation.calculateElevationData(from: altitudes)

        let pauseTouples = pauses.map { ($0.startDate, $0.endDate) }
        let durations = Computation.calculateDurationData(from: startDate, end: endDate, pauses: pauseTouples)

        let rawTalkDuration = voiceRecordings.reduce(0) { $0 + $1.duration }
        let talkDuration = min(rawTalkDuration, durations.activeDuration)

        let meditationIntervals = activityIntervals.filter { $0.activityType == .meditation }
        let rawMeditateDuration = meditationIntervals.reduce(0) { $0 + $1.startDate.distance(to: $1.endDate) }
        let clampedMeditateDuration = min(rawMeditateDuration, durations.activeDuration)

        super.init(
            uuid: nil,
            workoutType: workoutType,
            distance: distance,
            steps: steps,
            startDate: startDate,
            endDate: endDate,
            burnedEnergy: burnedEnergy,
            isRace: isRace,
            comment: comment,
            isUserModified: isUserModified,
            healthKitUUID: nil,
            finishedRecording: finishedRecording,
            ascend: elevation.ascending,
            descend: elevation.descending,
            activeDuration: durations.activeDuration,
            pauseDuration: durations.pauseDuration,
            dayIdentifier: CustomDateFormatting.dayIdentifier(forDate: startDate),
            talkDuration: talkDuration,
            meditateDuration: clampedMeditateDuration,
            heartRates: heartRates,
            routeData: routeData,
            pauses: pauses,
            workoutEvents: workoutEvents,
            voiceRecordings: voiceRecordings,
            activityIntervals: activityIntervals,
            waypoints: waypoints
        )
        self.weatherCondition = weatherCondition
        self.weatherTemperature = weatherTemperature
        self.weatherHumidity = weatherHumidity
        self.weatherWindSpeed = weatherWindSpeed
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    
    
}
