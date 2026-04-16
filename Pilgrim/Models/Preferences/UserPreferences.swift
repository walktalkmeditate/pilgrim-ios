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

    static let hemisphereOverride = UserPreference.Optional<Int>(key: "hemisphereOverride")

    static let soundsEnabled = UserPreference.Required<Bool>(key: "soundsEnabled", defaultValue: true)
    static let bellHapticEnabled = UserPreference.Required<Bool>(key: "bellHapticEnabled", defaultValue: true)
    static let bellVolume = UserPreference.Required<Double>(key: "bellVolume", defaultValue: 0.7)
    static let soundscapeVolume = UserPreference.Required<Double>(key: "soundscapeVolume", defaultValue: 0.4)
    // Bell and soundscape preferences have NO defaultValue set because
    // all of them support a valid "None" selection. If they had a
    // defaultValue fallback, setting the preference to nil (None) would
    // immediately read back as the default, making None impossible to
    // persist. Initial seeding for fresh installs and pre-migration
    // users happens once at app launch via a migration in
    // `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    static let walkStartBellId = UserPreference.Optional<String>(key: "walkStartBellId")
    static let walkEndBellId = UserPreference.Optional<String>(key: "walkEndBellId")
    static let meditationStartBellId = UserPreference.Optional<String>(key: "meditationStartBellId")
    static let meditationEndBellId = UserPreference.Optional<String>(key: "meditationEndBellId")
    static let selectedSoundscapeId = UserPreference.Optional<String>(key: "selectedSoundscapeId")
    static let breathRhythm = UserPreference.Required<Int>(key: "breathRhythm", defaultValue: 0)

    static let voiceGuideEnabled = UserPreference.Required<Bool>(key: "voiceGuideEnabled", defaultValue: false)
    static let selectedVoiceGuidePackId = UserPreference.Optional<String>(key: "selectedVoiceGuidePackId")
    static let meditationGuideEnabled = UserPreference.Required<Bool>(key: "meditationGuideEnabled", defaultValue: true)
    static let voiceGuideVolume = UserPreference.Required<Double>(key: "voiceGuideVolume", defaultValue: 0.8)
    static let voiceGuideDuckLevel = UserPreference.Required<Double>(key: "voiceGuideDuckLevel", defaultValue: 0.15)

    static let contributeToCollective = UserPreference.Required<Bool>(key: "contributeToCollective", defaultValue: false)
    static let lastSeenCollectiveWalks = UserPreference.Required<Int>(key: "lastSeenCollectiveWalks", defaultValue: 0)

    static let autoPlayWhisperOnProximity = UserPreference.Required<Bool>(key: "autoPlayWhisperOnProximity", defaultValue: true)

    static let beginWithIntention = UserPreference.Required<Bool>(key: "beginWithIntention", defaultValue: false)

    static let celestialAwarenessEnabled = UserPreference.Required<Bool>(key: "celestialAwarenessEnabled", defaultValue: false)

    static let walkReliquaryEnabled = UserPreference.Required<Bool>(key: "walkReliquaryEnabled", defaultValue: false)
    static let zodiacSystem = UserPreference.Required<String>(key: "zodiacSystem", defaultValue: "tropical")
    static let appearanceMode = UserPreference.Required<String>(key: "appearanceMode", defaultValue: "system")

    static let dynamicVoiceEnabled = UserPreference.Required<Bool>(key: "dynamicVoiceEnabled", defaultValue: true)
    static let autoTranscribe = UserPreference.Required<Bool>(key: "autoTranscribe", defaultValue: false)

    static let podcastConsentGiven = UserPreference.Required<Bool>(key: "podcastConsentGiven", defaultValue: false)
    static let lastPodcastSubmissionDate = UserPreference.Optional<String>(key: "lastPodcastSubmissionDate")

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

    static func applyUnitSystem(metric: Bool) {
        if metric {
            distanceMeasurementType.value = .kilometers
            altitudeMeasurementType.value = .meters
            speedMeasurementType.value = .minutesPerLengthUnit(from: .kilometers)
            weightMeasurementType.value = .kilograms
            energyMeasurementType.value = .kilojoules
        } else {
            distanceMeasurementType.value = .miles
            altitudeMeasurementType.value = .feet
            speedMeasurementType.value = .minutesPerLengthUnit(from: .miles)
            weightMeasurementType.value = .pounds
            energyMeasurementType.value = .kilocalories
        }
    }

}
