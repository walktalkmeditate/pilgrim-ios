//
//  WalkEvent.swift
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

public typealias WalkEvent = PilgrimV1.WorkoutEvent

public extension WalkEvent {
    
    enum EventType: CustomStringConvertible, CustomDebugStringConvertible, RawRepresentable, ImportableAttributeType, Codable {
        case lap, marker, segment, unknown
        
        public init(rawValue: Int) {
            switch rawValue {
            case 0:
                self = .lap
            case 1:
                self = .marker
            case 2:
                self = .segment
            default:
                self = .unknown
            }
        }
        
        public var rawValue: Int {
            switch self {
            case .lap:
                return 0
            case .marker:
                return 1
            case .segment:
                return 2
            case .unknown:
                return -1
            }
        }
        
        public var description: String {
            switch self {
            case .lap:
                return LS["WalkEvent.Type.Lap"]
            case .marker:
                return LS["WalkEvent.Type.Marker"]
            case .segment:
                return LS["WalkEvent.Type.Segment"]
            case .unknown:
                return LS["WalkEvent.Type.Unknown"]
            }
        }
        
        public var debugDescription: String {
            switch self {
            case .lap:
                return "Lap"
            case .marker:
                return "Marker"
            case .segment:
                return "Segment"
            case .unknown:
                return "Unknown"
            }
        }
        
    }
    
}

// MARK: - CustomStringConvertible

extension WalkEvent: CustomStringConvertible {
    
    public var description: String {
        var desc = "WalkEvent("
            
        if let uuid = uuid {
            desc += "uuid: \(uuid), "
        }
        
        return desc + "type: \(eventType.debugDescription), timestamp: \(timestamp)"
    }
}

// MARK: - WalkEventInterface

extension WalkEvent: WalkEventInterface {
    
    public var uuid: UUID? { threadSafeSyncReturn { self._uuid.value } }
    public var eventType: EventType { threadSafeSyncReturn { self._eventType.value } }
    public var timestamp: Date { threadSafeSyncReturn { self._timestamp.value } }
    public var workout: WalkInterface? { self._workout.value }
    
}

// MARK: - TempValueConvertible

extension WalkEvent: TempValueConvertible {
    
    public var asTemp: TempWalkEvent {
        TempWalkEvent(
            uuid: uuid,
            eventType: eventType,
            timestamp: timestamp
        )
    }
    
}


