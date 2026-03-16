//
//  WalkPause.swift
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
import CoreStore

public typealias WalkPause = PilgrimV5.WorkoutPause

extension PilgrimV2.WorkoutPause {

    public enum PauseType: RawRepresentable, ImportableAttributeType, Codable {

        case manual
        case automatic

        public init(rawValue: Int) {
            switch rawValue {
            case 1:
                self = .automatic
            default:
                self = .manual
            }
        }

        public var rawValue: Int {
            switch self {
            case .manual:
                return 0
            case .automatic:
                return 1
            }
        }
    }

}

public extension WalkPause {

    typealias PauseType = PilgrimV2.WorkoutPause.PauseType

}

// MARK: - CustomStringConvertible

extension WalkPause: CustomStringConvertible {
    
    public var description: String {
        var desc = "WalkPause("
            
        if let uuid = uuid {
            desc += "uuid: \(uuid), "
        }
            
        return desc + "start: \(startDate), end: \(endDate), duration: \(duration))"
    }
}

// MARK: - WalkPauseInterface

extension WalkPause: WalkPauseInterface {
    
    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var startDate: Date { threadSafeSyncReturn { self._startDate.value } }
    public var endDate: Date { threadSafeSyncReturn { self._endDate.value } }
    public var pauseType: PauseType { threadSafeSyncReturn { self._pauseType.value } }
    public var workout: WalkInterface? { self._workout.value }
    
}

// MARK: - TempValueConvertible

extension WalkPause: TempValueConvertible {
    
    public var asTemp: TempWalkPause {
        TempWalkPause(
            uuid: uuid,
            startDate: startDate,
            endDate: endDate,
            pauseType: pauseType
        )
    }
    
}
