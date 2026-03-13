//
//  WalkInterface.swift
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

/// A protocol to unify the saving and processing of objects holding walk data.
public protocol WalkInterface: DataInterface {
    
    /// The type of the underlying walk. For more see `Walk.WalkType`.
    var workoutType: Walk.WalkType { get }
    /// The distance travelled during the walk in meters.
    var distance: Double { get }
    /// The steps taken during the walk. If `nil`, no steps were recorded or it does not make sense to assign a step value to the walk because of its type.
    var steps: Int? { get }
    /// The `Date` the walk was started at.
    var startDate: Date { get }
    /// The `Date` the walk was ended at.
    var endDate: Date { get }
    /// An estimate of energy burned during the walk in kilocalories. If `nil` no estimate could be made or the walk was imported without data being attached.
    var burnedEnergy: Double? { get }
    /// A boolean indicating whether the recorded walk was a competition.
    var isRace: Bool { get }
    /// A `String` providing additional information on a walk. If `nil` none has been set.
    var comment: String? { get }
    /// A boolean indicating whether the walk was modified be the user.
    var isUserModified: Bool { get }
    /// The universally unique identifier provided by Apple Health and attached to the walk if it was imported from or saved to the HealthStore. If `nil` there is no known reference to the walk in Apple Health.
    var healthKitUUID: UUID? { get }
    /// A boolean indicating whether the walk recording has been finished yet.
    var finishedRecording: Bool { get }
    /// The height gained during the walk in meters.
    var ascend: Double { get }
    /// The height lossed during the walk in meters.
    var descend: Double { get }
    /// The duration the user was actively working out, meaning the walk was neither automatically nor manually paused.
    var activeDuration: Double { get }
    /// The duration the walk was paused.
    var pauseDuration: Double { get }
    /// A String to identify the specific day a walk was recorded on taken from the `startDate` property. The format of the date is `yyyyMMdd`.
    var dayIdentifier: String { get }
    /// A reference to `HeartRateDataSample`s associated with this walk.
    var heartRates: [HeartRateDataSampleInterface] { get }
    /// A reference to `RouteDataSamples` associated with this walk.
    var routeData: [RouteDataSampleInterface] { get }
    /// A reference to `WalkPause`s associated with this walk.
    var pauses: [WalkPauseInterface] { get }
    /// A reference to `WalkEvent`s associated with this walk.
    var workoutEvents: [WalkEventInterface] { get }
    /// A reference to `Event`s associated with this walk.
    var events: [EventInterface] { get }
    /// Duration spent talking (voice recording) in seconds.
    var talkDuration: Double { get }
    /// Duration spent meditating (stationary) in seconds.
    var meditateDuration: Double { get }
    /// A reference to voice recordings associated with this walk.
    var voiceRecordings: [VoiceRecordingInterface] { get }
    /// A reference to activity intervals associated with this walk.
    var activityIntervals: [ActivityIntervalInterface] { get }

}

public extension WalkInterface {
    
    var workoutType: Walk.WalkType { throwOnAccess() }
    var distance: Double { throwOnAccess() }
    var steps: Int? { throwOnAccess() }
    var startDate: Date { throwOnAccess() }
    var endDate: Date { throwOnAccess() }
    var burnedEnergy: Double? { throwOnAccess() }
    var isRace: Bool { throwOnAccess() }
    var comment: String? { throwOnAccess() }
    var isUserModified: Bool { throwOnAccess() }
    var healthKitUUID: UUID? { throwOnAccess() }
    var finishedRecording: Bool { throwOnAccess() }
    var ascend: Double { throwOnAccess() }
    var descend: Double { throwOnAccess() }
    var activeDuration: Double { throwOnAccess() }
    var pauseDuration: Double { throwOnAccess() }
    var dayIdentifier: String { throwOnAccess() }
    var heartRates: [HeartRateDataSampleInterface] { throwOnAccess() }
    var routeData: [RouteDataSampleInterface] { throwOnAccess() }
    var pauses: [WalkPauseInterface] { throwOnAccess() }
    var workoutEvents: [WalkEventInterface] { throwOnAccess() }
    var talkDuration: Double { throwOnAccess() }
    var meditateDuration: Double { throwOnAccess() }
    var events: [EventInterface] { throwOnAccess() }
    var voiceRecordings: [VoiceRecordingInterface] { throwOnAccess() }
    var activityIntervals: [ActivityIntervalInterface] { [] }

}
