//
//  WalkPauseInterface.swift
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

/// A protocol to unify the saving and processing of pause objects connected to a walk.
public protocol WalkPauseInterface: DataInterface {
    
    /// The `Date` the pause started at.
    var startDate: Date { get }
    /// The `Date` the pause ended at.
    var endDate: Date { get }
    /// The type of the pause. For more see `WalkPause.PauseType`.
    var pauseType: WalkPause.PauseType { get }
    /// A reference to the `Walk` this pause is associated with.
    var workout: WalkInterface? { get }
    
}

public extension WalkPauseInterface {
    
    var startDate: Date { throwOnAccess() }
    var endDate: Date { throwOnAccess() }
    var pauseType: WalkPause.PauseType { throwOnAccess() }
    var workout: WalkInterface? { throwOnAccess() }
    
    /// The duration of a pause, meaning the distance between the start and end date.
    var duration: TimeInterval {
        return startDate.distance(to: endDate)
    }
    
    /**
     Conversion of the TempWalkPause object into a Range.
     - parameter date: the reference date for forming the intervals
     - returns: a `ClosedRange` of type Double ranging from the start to the end interval of the `TempWalkPause` in perspective to the provided date
    */
    func asRange(from date: Date) -> ClosedRange<Double> {
        
        let startInterval = self.startDate.distance(to: date)
        let endInterval = self.endDate.distance(to: date)
        
        return startInterval...endInterval
        
    }
    
    /**
     Checks if a date is contained in the date range of a pause object.
     - parameter date: the date that is supposed to be checked
     - returns: a boolean indicating whether the date is contained within the pause data range
     */
    func contains(_ date: Date) -> Bool {
        return (startDate...endDate).contains(date)
    }
    
}
