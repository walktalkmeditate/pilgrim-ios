//
//  AutoPauseDetection.swift
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
import Combine
import CombineExt

/// A `WalkBuilderComponent` for detecting automatic pauses during a walk
public class AutoPauseDetection: WalkBuilderComponent {
    
    /// The current status of the bound walk builder.
    private var currentStatus: WalkBuilder.Status = .waiting
    /// The current predicted start date for an automatic pause.
    private var currentPredictedStartDate: Date?
    
    // MARK: - Dataflow
    
    /// An Array of cancellables for binding to the walk builder.
    private var cancellables: [AnyCancellable] = []
    
    /// The relay to suggest a new status to the `WalkBuilder`.
    private let statusSuggestionRelay = PassthroughRelay<WalkBuilder.Status>()
    
    // MARK: Binders
    
    /// Binds status updates to this component.
    private var statusBinder: (WalkBuilder.Status) -> Void {
        return { [weak self] newStatus in
            guard let self else { return }
            self.currentStatus = newStatus
            if newStatus == .recording {
                self.currentPredictedStartDate = nil
            }
        }
    }
    
    /// Binds location updates together with latest status to this component.
    private var updateBinder: ((TempRouteDataSample, Walk.WalkType)) -> Void {
        return { [weak self] value in
            guard let self else { return }
            let (location, workoutType) = value
            guard !(self.currentStatus == .paused), self.currentStatus.isActiveStatus, location.speed >= 0, ![.walking, .hiking].contains(workoutType) else { return }
            
            // looking for end date
            ifStatement: if self.currentPredictedStartDate != nil {
                guard location.speed >= 0.5 else { break ifStatement }
                self.statusSuggestionRelay.accept(.recording)
                
            // looking for start date
            } else {
                guard location.speed <= 0.25 else { break ifStatement }
                self.currentPredictedStartDate = location.timestamp
                self.statusSuggestionRelay.accept(.autoPaused)
            }
        }
    }
    
    /// Binds a reset event to this component.
    private var resetBinder: (WalkInterface?) -> Void {
        return { [weak self] snapshot in
            guard let self else { return }
            self.currentPredictedStartDate = snapshot?.endDate
        }
    }
    
    // MARK: WalkBuilderComponent
    
    public required init(builder: WalkBuilder) {
        self.bind(builder: builder)
    }
    
    public func bind(builder: WalkBuilder) {
        
        let input = Input(statusSuggestion: statusSuggestionRelay.asBackgroundPublisher())
        let output = builder.tranform(input)
        
        output.status.sink(receiveValue: statusBinder).store(in: &cancellables)
        output.onReset.sink(receiveValue: resetBinder).store(in: &cancellables)
        
        output.currentLocation
            .compactMap { $0 }
            .combineLatest(output.workoutType)
            .sink(receiveValue: updateBinder)
            .store(in: &cancellables)
    }
}
