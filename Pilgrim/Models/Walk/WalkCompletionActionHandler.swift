//
//  WalkCompletionActionHandler.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
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

class WalkCompletionActionHandler {
    
    /// A `TempWalk` object to be saved, discarded or handed back to a `WalkBuilder` by this class
    private var snapshot: TempWalk
    
    /// A weak reference to a `WalkBuilder` to continue the walk
    private weak var builder: WalkBuilder?
    
    /// If `true` the `WalkCompletionActionHandler` did already perform an action, so no additional action should be taken
    private var didPerformAction: Bool = false
    
    /**
     Initialises the `WalkCompletionActionHandler` with the needed snapshot of an `TempWalk`
     - parameter snapshot: a `TempWalk` object to be saved, discarded or continued
     */
    public init(snapshot: TempWalk, builder: WalkBuilder) {
        
        self.snapshot = snapshot
        self.builder = builder
        
    }
    
    /**
     Displays a dismissable view over the current `UIWindow` that gives the user options on what to do with the just recorded walk, saving it automatically after a certain time
     */
    public func display() {
        // would normally show save banner
    }
    
    /**
     Saves the walk if no other action was already performed
     */
    public func saveWalk() {
        
        guard !self.didPerformAction else {
            return
        }
        
        self.didPerformAction = true
        
        DataManager.saveWalk(object: self.snapshot) { (success, error, walk) in
            // would normally show save success banner
        }
        
    }
    
    /**
     Continues the walk if no other action was already performed and the builder is still active
     */
    public func continueWalk() {
        
        guard !self.didPerformAction else {
            return
        }
        
        self.didPerformAction = true
        
        var messageKey = ""
        
        if let builder = self.builder {
            
            builder.continueWalk(from: self.snapshot)
            
            messageKey = "NewWalkCompletion.Continue.Success"
            
        } else {
            
            messageKey = "NewWalkCompletion.Continue.Error"
            
        }
        
        // would normally show continuing or error banner
        
        print("Imagine the walk would continue")
        
    }
    
    /**
     Discards the walk if no other action was already performed
     */
    public func discardWalk() {
        
        guard !self.didPerformAction else {
            return
        }
        
        self.didPerformAction = true
        
    }
    
}
