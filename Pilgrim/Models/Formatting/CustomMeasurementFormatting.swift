//
//  CustomMeasurementFormatting.swift
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

class CustomMeasurementFormatting {
    
    static func string(forMeasurement measurement: NSMeasurement, type: FormattingMeasurementType = .auto, rounding: FormattingRoundingType = .twoDigits) -> String {

        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit

        switch rounding {
        case .wholeNumbers:
            formatter.numberFormatter.roundingIncrement = 1
        case .oneDigit:
            formatter.numberFormatter.roundingIncrement = 0.1
        case .twoDigits:
            formatter.numberFormatter.roundingIncrement = 0.01
        case .fourDigits:
            formatter.numberFormatter.roundingIncrement = 0.0001
        case .none:
            break
        }

        let type = type == .auto ? FormattingMeasurementType(for: measurement.unit) : type

        switch type {
        case .clock, .pace:
            let seconds = safeMeasurementValue(measurement, to: UnitDuration.seconds)
            let timeFormatter = DateComponentsFormatter()
            timeFormatter.unitsStyle = .positional
            timeFormatter.allowedUnits = type == .pace ? [.minute, .second] : [.hour, .minute, .second]
            timeFormatter.zeroFormattingBehavior = .pad
            return timeFormatter.string(from: seconds) ?? "Error"
        case .distance:
            return safeFormattedString(formatter, measurement: measurement, to: UserPreferences.distanceMeasurementType.safeValue)
        case .altitude:
            return safeFormattedString(formatter, measurement: measurement, to: UserPreferences.altitudeMeasurementType.safeValue)
        case .speed:
            return safeFormattedString(formatter, measurement: measurement, to: UserPreferences.speedMeasurementType.safeValue)
        case .energy:
            return safeFormattedString(formatter, measurement: measurement, to: UserPreferences.energyMeasurementType.safeValue)
        case .weight:
            return safeFormattedString(formatter, measurement: measurement, to: UserPreferences.weightMeasurementType.safeValue)
        default:
            return formatter.string(from: Measurement(value: measurement.doubleValue, unit: measurement.unit))
        }
    }

    private static func canConvert(_ measurement: NSMeasurement, to target: Unit) -> Bool {
        guard let sourceDimension = measurement.unit as? Dimension,
              let targetDimension = target as? Dimension else { return false }
        return type(of: sourceDimension) == type(of: targetDimension)
    }

    private static func safeMeasurementValue(_ measurement: NSMeasurement, to target: Unit) -> Double {
        guard canConvert(measurement, to: target) else { return measurement.doubleValue }
        return measurement.converting(to: target).value
    }

    private static func safeFormattedString(_ formatter: MeasurementFormatter, measurement: NSMeasurement, to target: Unit) -> String {
        guard canConvert(measurement, to: target) else {
            return formatter.string(from: Measurement(value: measurement.doubleValue, unit: measurement.unit))
        }
        return formatter.string(from: measurement.converting(to: target))
    }
    
    static func string(forUnit unit: Unit, short: Bool = false) -> String {
        let formatter = MeasurementFormatter()
        return short ? unit.symbol : formatter.string(from: unit)
    }
    
    enum FormattingMeasurementType {
        case clock, time, pace
        case distance, altitude
        case speed
        case energy
        case weight
        case count
        case auto
        
        init(for unit: Unit, asClock: Bool = false, asAltitude: Bool = false) {
            switch unit {
            case is UnitDuration:
                self = asClock ? .clock : .time
            case is UnitLength:
                self = asAltitude ? .altitude : .distance
            case is UnitSpeed:
                let isPace = [UnitSpeed.minutesPerLengthUnit(from: .kilometers) as Unit, UnitSpeed.minutesPerLengthUnit(from: .miles) as Unit].contains(unit)
                self = isPace ? .pace : .speed
            case is UnitEnergy:
                self = .energy
            case is UnitMass:
                self = .weight
            case is UnitCount:
                self = .count
            default:
                self = .auto
            }
        }
    }
    
    enum FormattingRoundingType {
        case wholeNumbers, oneDigit, twoDigits, fourDigits, none
    }
    
}
