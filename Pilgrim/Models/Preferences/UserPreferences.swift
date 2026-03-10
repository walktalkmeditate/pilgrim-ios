//
//  UserPreferences.swift
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

import UIKit

struct UserPreferences {

    static let isSetUp = UserPreference.Required<Bool>(key: "isSetUp", defaultValue: false)

    static let name = UserPreference.Optional<String>(key: "name")
    static let weight = UserPreference.Optional<Double>(key: "weight")

    static let shouldShowMap = UserPreference.Required<Bool>(key: "shouldShowMap", defaultValue: true)
    static let gpsAccuracy = UserPreference.Optional<Double>(key: "gpsAccuracy", initialValue: nil)

    static let distanceMeasurementType = MeasurementUserPreference<UnitLength>(key: "distanceMeasurementType", possibleValues: [.kilometers, .miles])
    static let altitudeMeasurementType = MeasurementUserPreference<UnitLength>(key: "altitudeMeasurementType", possibleValues: [.meters, .feet], bigUnits: false)
    static let speedMeasurementType = MeasurementUserPreference<UnitSpeed>(key: "speedMeasurementType", possibleValues: [.kilometersPerHour, .milesPerHour, .minutesPerLengthUnit(from: .kilometers), .minutesPerLengthUnit(from: .miles)])
    static let energyMeasurementType = MeasurementUserPreference<UnitEnergy>(key: "energyMeasurementType", possibleValues: [.kilojoules, .kilocalories])
    static let weightMeasurementType = MeasurementUserPreference<UnitMass>(key: "weightMeasurementType", possibleValues: [.kilograms, .pounds])

    static func reset() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }

}
