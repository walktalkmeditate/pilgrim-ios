//
//  LiveStats.swift
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
import CoreLocation

class LiveStats: WalkBuilderComponent {
    
    // MARK: - Dataflow
    
    /// An Array of cancellables for binding to the walk builder.
    private var cancellables: [AnyCancellable] = []
    
    /// The relay to publish the current status of the `WalkBuilder`.
    fileprivate let statusRelay = CurrentValueRelay<WalkBuilder.Status>(.waiting)
    /// The relay to publish the type of walk the `WalkBuilder` is supposed to record.
    fileprivate let workoutTypeRelay = CurrentValueRelay<Walk.WalkType?>(nil)
    /// The relay to publish the distance shared by components.
    fileprivate let distanceRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UserPreferences.distanceMeasurementType.safeValue))
    fileprivate let rawDistanceRelay = CurrentValueRelay<Double>(0)
    /// The relay to publish the steps counted by components.
    fileprivate let stepsRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UnitCount.count))
    /// The relay to publish the current location regardless of whether it was recorded or not.
    fileprivate let currentLocationRelay = CurrentValueRelay<TempRouteDataSample?>(nil)
    /// The relay to publish the recorded locations received from components.
    fileprivate let locationsRelay = CurrentValueRelay<[TempRouteDataSample]>([])
    /// The relay to publish the heart rate samples received from components.
    fileprivate let currentHeartRateRelay = CurrentValueRelay<TempHeartRateDataSample?>(nil)
    /// The relay to publish a components report of isufficient permissions to record the walk.
    fileprivate let insufficientPermissionRelay = PassthroughRelay<String>()
    
    /// The relay to publish a string describing the elapsed duration of the walk.
    fileprivate let durationRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UnitDuration.seconds, type: .clock))
    /// The relay to publish the energy burned during the walk as computed periodically.
    fileprivate let burnedEnergyRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UserPreferences.energyMeasurementType.safeValue))
    fileprivate let ascentRelay = CurrentValueRelay<String>(StatsHelper.string(for: 0, unit: UnitLength.meters, type: .altitude))
    
    // MARK: Binders
    
    /// Maps distance updates to a desired output.
    private var distanceMapper: (Double) -> String = { distance in
        return StatsHelper.string(for: distance, unit: UnitLength.standardUnit)
    }
    
    /// Maps distance updates to a desired output.
    private var stepsMapper: (Int?) -> String = { steps in
        return StatsHelper.string(for: Double(steps), unit: UnitCount.count)
    }
    
    private var ascentMapper: ([AltitudeManagement.AltitudeSample]) -> String = { samples in
        guard samples.count > 1 else {
            return StatsHelper.string(for: 0, unit: UnitLength.meters, type: .altitude)
        }
        var totalAscent: Double = 0
        for i in 1..<samples.count {
            let diff = samples[i].altitude - samples[i - 1].altitude
            if diff > 0.3 {
                totalAscent += diff
            }
        }
        return StatsHelper.string(for: totalAscent, unit: UnitLength.meters, type: .altitude)
    }
    
    // MARK: - Publishers
    
    var status: AnyPublisher<WalkBuilder.Status, Never> { self.statusRelay.eraseToAnyPublisher() }
    var workoutType: AnyPublisher<Walk.WalkType?, Never> { self.workoutTypeRelay.eraseToAnyPublisher() }
    var distance: AnyPublisher<String, Never> { self.distanceRelay.eraseToAnyPublisher() }
    var rawDistance: AnyPublisher<Double, Never> { self.rawDistanceRelay.eraseToAnyPublisher() }
    var steps: AnyPublisher<String, Never> { self.stepsRelay.eraseToAnyPublisher() }
    var currentLocation: AnyPublisher<TempRouteDataSample?, Never> { self.currentLocationRelay.eraseToAnyPublisher() }
    var locations: AnyPublisher<[TempRouteDataSample], Never> { self.locationsRelay.eraseToAnyPublisher() }
    var currentHeartRate: AnyPublisher<TempHeartRateDataSample?, Never> { self.currentHeartRateRelay.eraseToAnyPublisher() }
    var insufficientPermission: AnyPublisher<String, Never> { self.insufficientPermissionRelay.eraseToAnyPublisher() }
    var duration: AnyPublisher<String, Never> { self.durationRelay.eraseToAnyPublisher() }
    var burnedEnergy: AnyPublisher<String, Never> { self.burnedEnergyRelay.eraseToAnyPublisher() }
    var ascent: AnyPublisher<String, Never> { self.ascentRelay.eraseToAnyPublisher() }
    
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
        output.distance.sink(receiveValue: rawDistanceRelay.accept).store(in: &cancellables)
        output.steps.map(stepsMapper).sink(receiveValue: stepsRelay.accept).store(in: &cancellables)
        output.currentLocation.sink(receiveValue: currentLocationRelay.accept).store(in: &cancellables)
        output.locations.sink(receiveValue: locationsRelay.accept).store(in: &cancellables)
        output.heartRates.map { $0.last }.sink(receiveValue: currentHeartRateRelay.accept).store(in: &cancellables)
        output.insufficientPermission.sink(receiveValue: insufficientPermissionRelay.accept).store(in: &cancellables)
        
        output.altitudes
            .map(ascentMapper)
            .sink(receiveValue: ascentRelay.accept)
            .store(in: &cancellables)

        // The `duration` and `burnedEnergy` publishers below have no
        // subscribers during a walk: ActiveWalkViewModel computes duration
        // with its own 1 Hz timer, and burned energy is computed once at
        // save time in NewWalk. Running their 1 Hz combineLatest pipelines
        // here was pure dead cost on the most battery-sensitive screen (P5),
        // so they are not wired up. The relays keep their default values for
        // any future consumer; nothing recomputes them on a timer.
    }
}
