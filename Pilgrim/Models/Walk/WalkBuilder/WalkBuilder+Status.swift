//
//  WalkBuilder+Status.swift
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
import UIKit

extension WalkBuilder {
    
    /**
     Enumaration of the different kind of status the `WalkBuilder` can take on
     */
    public enum Status {
        
        /// indicating that the `WalkBuilder` is neither recording nor ready to do so, but instead waiting for all components to be ready
        case waiting
        /// indicating that the `WalkBuilder` is ready to record a walk
        case ready
        /// indicating that the `WalkBuilder` is recording a walk at the moment
        case recording
        /// indicating that the `WalkBuilder` was manually paused by the user, data is still supposed to be recorded in the background and the walk might be resumed at any point in time
        case paused
        /// indicating that the `WalkBuilder` was paused by the automatic pause detection, it should act as if it was manually paused, which a user should still be able to do in this scenario
        case autoPaused
        
        /// a localised title for the status
        public var title: String {
            switch self {
            case .waiting:
                return LS["WalkBuilder.Status.Waiting"]
            case .ready:
                return LS["WalkBuilder.Status.Ready"]
            case .recording:
                return LS["WalkBuilder.Status.Recording"]
            case .paused:
                return LS["WalkBuilder.Status.Paused"]
            case .autoPaused:
                return LS["WalkBuilder.Status.AutoPaused"]
            }
            
        }
        
        /// a color representing the status
        public var color: UIColor {
            switch self {
            case .waiting:
                return .yellow
            case .ready:
                return .green
            case .recording:
                return .red
            case .paused, .autoPaused:
                return .systemGray
            }
        }
        
        /// a boolean indicating whether the status is a paused status
        public var isPausedStatus: Bool {
            return [.paused, .autoPaused].contains(self)
        }
        
        /// a boolean indicating whether the status is an active status meaning data is recorded while one of these status is the current one
        public var isActiveStatus: Bool {
            return [.recording, .paused, .autoPaused].contains(self)
        }
    }
    
}
