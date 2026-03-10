//
//  LiveStats.swift
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
import Combine
import CombineExt
import CoreLocation

class LiveStats: WalkBuilderComponent {
    
    // MARK: - Dataflow
    
    /// An Array of cancellables for binding to the workout builder.
    private var cancellables: [AnyCancellable] = []
    
    /// The relay to publish the current status of the `WalkBuilder`.
    fileprivate let statusRelay = CurrentValueRelay<WalkBuilder.Status>(.waiting)
    /// The relay to publish the type of workout the `WalkBuilder` is supposed to record.
    fileprivate let workoutTypeRelay = CurrentValueRelay<Walk.WalkType?>(nil)
    /// The relay to publish the distance shared by components.
    fileprivate let distanceRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UserPreferences.distanceMeasurementType.safeValue))
    /// The relay to publish the steps counted by components.
    fileprivate let stepsRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UnitCount.count))
    /// The relay to publish the current location regardless of whether it was recorded or not.
    fileprivate let currentLocationRelay = CurrentValueRelay<TempRouteDataSample?>(nil)
    /// The relay to publish the recorded locations received from components.
    fileprivate let locationsRelay = CurrentValueRelay<[TempRouteDataSample]>([])
    /// The relay to publish the heart rate samples received from components.
    fileprivate let currentHeartRateRelay = CurrentValueRelay<TempHeartRateDataSample?>(nil)
    /// The relay to publish a components report of isufficient permissions to record the workout.
    fileprivate let insufficientPermissionRelay = PassthroughRelay<String>()
    
    /// The relay to publish a string describing the elapsed duration of the workout.
    fileprivate let durationRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UnitDuration.seconds, type: .clock))
    /// The relay to publish the energy burned during the workout as computed periodically.
    fileprivate let burnedEnergyRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UserPreferences.energyMeasurementType.safeValue))
    /// The relay to publish the speed returned in meters per second.
    fileprivate let speedRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UserPreferences.speedMeasurementType.safeValue, type: (UserPreferences.speedMeasurementType.safeValue == UnitSpeed.minutesPerLengthUnit(from: UnitLength.standardBigLocalUnit as! UnitLength)) ? .pace : .auto))
    
    // MARK: Binders
    
    /// Maps distance updates to a desired output.
    private var distanceMapper: (Double) -> String = { distance in
        return StatsHelper.string(for: distance, unit: UnitLength.standardUnit)
    }
    
    /// Maps distance updates to a desired output.
    private var stepsMapper: (Int?) -> String = { steps in
        return StatsHelper.string(for: Double(steps), unit: UnitCount.count)
    }
    
    /// Maps to duration output.
    private var durationMapper: (Date, Date?, [TempWalkPause], Date?) -> String? = { _, startDate, pauses, endDate in
        guard let startDate = startDate else { return nil }
        let duration = startDate.distance(to: endDate ?? Date()) - pauses.map { $0.duration }.reduce(0, +)
        return StatsHelper.string(for: duration, unit: UnitDuration.seconds, type: .clock)
    }
    
    /// Maps to burned energy output.
    private var burnedEnergyMapper: (Date, Walk.WalkType, Double) -> String? = { _, workoutType, distance in
        guard let weight = UserPreferences.weight.value else { return nil }
        let burnedEnergy = Computation.calculateBurnedEnergy(for: workoutType, distance: distance, weight: weight)
        return StatsHelper.string(for: burnedEnergy, unit: UnitEnergy.standardUnit)
    }
    
    /// Uses the most recent GPS speed for responsive display.
    private var speedMapper: ([TempRouteDataSample], Date?, [TempWalkPause], Double) -> String? = { locations, startDate, pauses, distance in
        guard startDate != nil else { return nil }

        let speed = locations.last.map { max(0, $0.speed) } ?? 0.0

        return StatsHelper.string(for: speed, unit: UnitSpeed.standardUnit)
    }
    
    // MARK: - Publishers
    
    var status: AnyPublisher<WalkBuilder.Status, Never> { self.statusRelay.eraseToAnyPublisher() }
    var workoutType: AnyPublisher<Walk.WalkType?, Never> { self.workoutTypeRelay.eraseToAnyPublisher() }
    var distance: AnyPublisher<String, Never> { self.distanceRelay.eraseToAnyPublisher() }
    var steps: AnyPublisher<String, Never> { self.stepsRelay.eraseToAnyPublisher() }
    var currentLocation: AnyPublisher<TempRouteDataSample?, Never> { self.currentLocationRelay.eraseToAnyPublisher() }
    var locations: AnyPublisher<[TempRouteDataSample], Never> { self.locationsRelay.eraseToAnyPublisher() }
    var currentHeartRate: AnyPublisher<TempHeartRateDataSample?, Never> { self.currentHeartRateRelay.eraseToAnyPublisher() }
    var insufficientPermission: AnyPublisher<String, Never> { self.insufficientPermissionRelay.eraseToAnyPublisher() }
    var duration: AnyPublisher<String, Never> { self.durationRelay.eraseToAnyPublisher() }
    var burnedEnergy: AnyPublisher<String, Never> { self.burnedEnergyRelay.eraseToAnyPublisher() }
    var speed: AnyPublisher<String, Never> { self.speedRelay.eraseToAnyPublisher() }
    
    // MARK: WalkBuilderComponent
    
    public required init(builder: WalkBuilder) {
        self.bind(builder: builder)
    }
    
    func bind(builder: WalkBuilder) {
        
        self.cancellables = []
        let output = builder.tranform(Input())
            
        output.status.sink(receiveValue: statusRelay.accept).store(in: &cancellables)
        output.workoutType.sink(receiveValue: workoutTypeRelay.accept).store(in: &cancellables)
        output.distance.map(distanceMapper).sink(receiveValue: distanceRelay.accept).store(in: &cancellables)
        output.steps.map(stepsMapper).sink(receiveValue: stepsRelay.accept).store(in: &cancellables)
        output.currentLocation.sink(receiveValue: currentLocationRelay.accept).store(in: &cancellables)
        output.locations.sink(receiveValue: locationsRelay.accept).store(in: &cancellables)
        output.heartRates.map { $0.last }.sink(receiveValue: currentHeartRateRelay.accept).store(in: &cancellables)
        output.insufficientPermission.sink(receiveValue: insufficientPermissionRelay.accept).store(in: &cancellables)
        
        output.locations
            .combineLatest(output.startDate, output.pauses, output.distance)
            .compactMap(speedMapper)
            .sink(receiveValue: speedRelay.accept)
            .store(in: &cancellables)
        
        let periodicUpdates = Timer.TimerPublisher(interval: 1, runLoop: .main, mode: .default).autoconnect()
        
        periodicUpdates
            .combineLatest(output.startDate, output.pauses, output.endDate)
            .compactMap(durationMapper)
            .sink(receiveValue: durationRelay.accept)
            .store(in: &cancellables)
        
        periodicUpdates
            .combineLatest(output.workoutType, output.distance)
            .compactMap(burnedEnergyMapper)
            .sink(receiveValue: burnedEnergyRelay.accept)
            .store(in: &cancellables)
    }
}
