//
//  WalkStats.swift
//
//  Pilgrim
//  Copyright (C) 2021 Tim Fraedrich <timfraedrich@icloud.com>
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
import CoreLocation
import Combine

class WalkStats {
    
    let walk: WalkInterface
    
    let workoutType: Walk.WalkType
    
    let hasSteps: Bool
    let hasWalkPauses: Bool
    let hasWalkEvents: Bool
    let hasRouteSamples: Bool
    let hasHeartRateData: Bool
    let hasEnergyValue: Bool
    
    // DISTANCE
    let distance: AnyPublisher<String, Never>
    let steps: AnyPublisher<String?, Never>
    let ascendingAltitude: AnyPublisher<String?, Never>
    let descendingAltitude: AnyPublisher<String?, Never>
    let altitudeOverTime: AnyPublisher<WalkStatsSeries<Bool, Double, RouteDataSample>, Never>
    
    // DURATION
    let startDate: AnyPublisher<String, Never>
    let endDate: AnyPublisher<String, Never>
    let activeDuration: AnyPublisher<String, Never>
    let pauseDuration: AnyPublisher<String?, Never>
    
    // SPEED
    let averageSpeed: AnyPublisher<String, Never>
    let topSpeed: AnyPublisher<String, Never>
    let speedOverTime: AnyPublisher<WalkStatsSeries<Bool, Double, RouteDataSample>, Never>
    
    // ENERGY
    let burnedEnergy: AnyPublisher<String?, Never>
    var burnedEnergyPerMinute: AnyPublisher<String?, Never>
    
    // HEART RATE
    let averageHeartRate: AnyPublisher<String?, Never>
    let heartRateOverTime: AnyPublisher<WalkStatsSeries<Bool, Int, HeartRateDataSample>, Never>
    
    init(walk: Walk) {

        self.walk = walk

        self.workoutType = walk.workoutType

        self.hasSteps = walk.steps != nil
        self.hasWalkPauses = !walk.pauses.isEmpty
        self.hasWalkEvents = !walk.workoutEvents.isEmpty
        self.hasRouteSamples = !walk.routeData.isEmpty
        self.hasHeartRateData = !walk.heartRates.isEmpty
        self.hasEnergyValue = walk.burnedEnergy != nil

        self.distance = WalkStats.just(walk.distance, unit: UnitLength.standardUnit)
        self.steps = WalkStats.just(Double(walk.steps), unit: UnitCount.count)
        self.ascendingAltitude = WalkStats.just(walk.ascend, unit: UnitLength.meters, type: .altitude)
        self.descendingAltitude = WalkStats.just(walk.descend, unit: UnitLength.meters, type: .altitude)
        self.altitudeOverTime = WalkStats.unitSeries(from: walk, samples: \Walk._routeData.value, metric: \RouteDataSample._altitude.value, desiredUnit: UserPreferences.altitudeMeasurementType.safeValue)

        self.startDate = WalkStats.just(time: walk.startDate)
        self.endDate = WalkStats.just(time: walk.endDate)
        self.activeDuration = WalkStats.just(walk.activeDuration, unit: UnitDuration.seconds)
        self.pauseDuration = WalkStats.just(walk.pauseDuration, unit: UnitDuration.seconds)

        self.averageSpeed = WalkStats.just(walk.distance / walk.activeDuration, unit: UnitSpeed.metersPerSecond)
        self.topSpeed = WalkStats.just(walk.routeData.max{ $0.speed > $1.speed }?.speed, unit: UnitSpeed.metersPerSecond)
        self.speedOverTime = WalkStats.unitSeries(from: walk, samples: \Walk._routeData, metric: \RouteDataSample._speed.value, desiredUnit: UserPreferences.speedMeasurementType.safeValue)

        self.burnedEnergy = WalkStats.just(walk.burnedEnergy, unit: UnitEnergy.standardUnit)
        self.burnedEnergyPerMinute = WalkStats.just((walk.burnedEnergy ?? 0) / (walk.activeDuration / 60), unit: UnitPower.energyPerMinute(from: .kilocalories)) // find better solution

        self.averageHeartRate = WalkStats.just(Double(walk.heartRates.map { $0.heartRate }.reduce(0, +) / walk.heartRates.count), unit: UnitCount.count, type: .count)
        self.heartRateOverTime = WalkStats.series(from: walk, samples: \Walk._heartRates.value, metric: \HeartRateDataSample._heartRate.value)
    }
    
    /**
     Creates a static observable string driver from the provided time specified.
     - parameter time: the date from which the time should be formatted as a string
     - returns: a static observable string driver
     */
    private static func just(time: Date) -> AnyPublisher<String, Never> {
        
        return Just(CustomDateFormatting.timeString(forDate: time)).eraseToAnyPublisher()
    }
    
    /**
     Creates a static observable optional string driver from the provided value, unit and formating behaviour specified.
     - parameter value: the value supposed to be formatted
     - parameter unit: the unit in which the value is provided
     - parameter type: the type by which the value is formatted, `.auto` by default
     - parameter rounding: the type by which the value is rounded, `.twoDigits` by default
     - returns: a static observable optional string driver
     */
    private static func just(
        _ value: Double?,
        unit: Unit?,
        type: CustomMeasurementFormatting.FormattingMeasurementType = .auto,
        rounding: CustomMeasurementFormatting.FormattingRoundingType = .twoDigits
    ) -> AnyPublisher<String?, Never> {
        
        return Just(StatsHelper.string(for: value, unit: unit, type: type, rounding: rounding)).eraseToAnyPublisher()
    }
    
    /**
     Creates a static observable string driver from the provided value, unit and formating behaviour specified.
     - parameter value: the value supposed to be formatted
     - parameter unit: the unit in which the value is provided
     - parameter type: the type by which the value is formatted, `.auto` by default
     - parameter rounding: the type by which the value is rounded, `.twoDigits` by default
     - returns: a static observable string driver, the driver provides `"--"` if formatting fails
     */
    private static func just(
        _ value: Double?,
        unit: Unit?,
        type: CustomMeasurementFormatting.FormattingMeasurementType = .auto,
        rounding: CustomMeasurementFormatting.FormattingRoundingType = .twoDigits
    ) -> AnyPublisher<String, Never> {
        
        return just(value, unit: unit, type: type, rounding: rounding).map { $0 ?? "--" }.eraseToAnyPublisher()
    }
    
    /**
     Queries a series of a specific metric from specified samples relative to the start date of the walk and grouped by if they are paused or not.
     - parameter walk: the walk object used to query samples from
     - parameter samples: a keypath pointing to the samples of which the matric should be taken
     - parameter metric: a keypath pointing to the metric of the before specified sample
     - returns: a driver publishing the stats series
     */
    private static func series <SampleType: Collection, MetricType: Any> (
        from walk: WalkInterface,
        samples samplesPath: KeyPath<Walk, SampleType>,
        metric metricPath: KeyPath<SampleType.Element, MetricType>
    ) -> AnyPublisher<WalkStatsSeries<Bool, MetricType, SampleType.Element>, Never>
    where SampleType.Element: SampleInterface {

        return Publishers.Create { subscriber in
            var disposed = false
            DataManager.querySectionedMetrics(
                from: walk,
                samples: samplesPath,
                metric: metricPath,
                completion: { seriesData in
                    guard !disposed else { return }
                    subscriber.send(seriesData)
                    subscriber.send(completion: .finished)
                }
            )
            return AnyCancellable { disposed = true }
        }.eraseToAnyPublisher()
    }
    
    /**
     Queries a series of a specific `Double` metric converted to a desired unit from specified samples relative to the start date of the walk and grouped by if they are paused or not.
     - parameter walk: the walk object used to query samples from
     - parameter samples: a keypath pointing to the samples of which the matric should be taken
     - parameter metric: a keypath pointing to the metric of the before specified sample
     - parameter desiredUnit: the unit the metric should be converted to
     - returns: a driver publishing the stats series
     */
    private static func unitSeries <SampleType: Collection, UnitType: StandardizedUnit> (
        from walk: WalkInterface,
        samples samplesPath: KeyPath<Walk, SampleType>,
        metric metricPath: KeyPath<SampleType.Element, Double>,
        desiredUnit: UnitType
    ) -> AnyPublisher<WalkStatsSeries<Bool, Double, SampleType.Element>, Never>
    where SampleType.Element: SampleInterface {

        series(from: walk, samples: samplesPath, metric: metricPath)
            .map { series in
                return WalkStatsSeries(sections: series.sections.map { (sectionValue, data) in
                    let convertedData = data.map { (timestamp, value, object) -> (TimeInterval, Double, SampleType.Element?) in
                        let convertedValue = NSMeasurement(doubleValue: value, unit: UnitType.standardUnit).converting(to: desiredUnit).value
                        return (timestamp, convertedValue, object)
                    }
                    return (sectionValue, convertedData)
                })
            }.eraseToAnyPublisher()
    }
}
