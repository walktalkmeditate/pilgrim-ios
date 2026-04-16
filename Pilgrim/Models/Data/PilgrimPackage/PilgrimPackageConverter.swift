import Foundation

enum PilgrimPackageConverter {

    static let schemaVersion = "1.0"

    // MARK: - Walk Conversion

    /// `includePhotos: false` (the default) leaves `PilgrimWalk.photos` nil so
    /// the JSON encoder omits the key and the file stays byte-identical to
    /// the pre-reliquary format.
    static func convert(
        walk: WalkInterface,
        system: ZodiacSystem,
        celestialEnabled: Bool,
        includePhotos: Bool = false
    ) -> PilgrimWalk? {
        guard let id = walk.uuid else { return nil }

        let walkType: String = walk.workoutType == .walking ? "walking" : "unknown"

        let stats = PilgrimStats(
            distance: walk.distance,
            steps: walk.steps,
            activeDuration: walk.activeDuration,
            pauseDuration: walk.pauseDuration,
            ascent: walk.ascend,
            descent: walk.descend,
            burnedEnergy: walk.burnedEnergy,
            talkDuration: walk.talkDuration,
            meditateDuration: walk.meditateDuration
        )

        let weather: PilgrimWeather? = {
            guard let temp = walk.weatherTemperature,
                  let condition = walk.weatherCondition else { return nil }
            return PilgrimWeather(
                temperature: temp,
                condition: condition,
                humidity: walk.weatherHumidity,
                windSpeed: walk.weatherWindSpeed
            )
        }()

        let route = buildRouteGeoJSON(
            routeData: walk.routeData,
            waypoints: walk.waypoints
        )

        let pauses = walk.pauses.map { pause in
            PilgrimPause(
                startDate: pause.startDate,
                endDate: pause.endDate,
                type: pause.pauseType == .automatic ? "automatic" : "manual"
            )
        }

        let activities = walk.activityIntervals.map { interval in
            PilgrimActivity(
                type: interval.activityType == .meditation ? "meditation" : "unknown",
                startDate: interval.startDate,
                endDate: interval.endDate
            )
        }

        let voiceRecordings = walk.voiceRecordings.map { recording in
            PilgrimVoiceRecording(
                startDate: recording.startDate,
                endDate: recording.endDate,
                duration: recording.duration,
                transcription: recording.transcription,
                wordsPerMinute: recording.wordsPerMinute,
                isEnhanced: recording.isEnhanced
            )
        }

        let heartRates = walk.heartRates.map { sample in
            PilgrimHeartRate(timestamp: sample.timestamp, heartRate: sample.heartRate)
        }

        let workoutEvents = walk.workoutEvents.map { event in
            PilgrimWorkoutEvent(
                timestamp: event.timestamp,
                type: workoutEventTypeString(event.eventType)
            )
        }

        return PilgrimWalk(
            schemaVersion: schemaVersion,
            id: id,
            type: walkType,
            startDate: walk.startDate,
            endDate: walk.endDate,
            stats: stats,
            weather: weather,
            route: route,
            pauses: pauses,
            activities: activities,
            voiceRecordings: voiceRecordings,
            intention: walk.comment,
            reflection: celestialEnabled ? buildReflection(date: walk.startDate, system: system) : nil,
            heartRates: heartRates,
            workoutEvents: workoutEvents,
            favicon: walk.favicon,
            isRace: walk.isRace,
            isUserModified: walk.isUserModified,
            finishedRecording: walk.finishedRecording,
            photos: PilgrimPackagePhotoConverter.exportPhotos(from: walk.walkPhotos, includePhotos: includePhotos)
        )
    }

    // MARK: - GeoJSON

    static func buildRouteGeoJSON(
        routeData: [RouteDataSampleInterface],
        waypoints: [WaypointInterface]
    ) -> GeoJSONFeatureCollection {
        var features: [GeoJSONFeature] = []

        if !routeData.isEmpty {
            var coordinates: [[Double]] = []
            var timestamps: [Date] = []
            var speeds: [Double] = []
            var directions: [Double] = []
            var horizontalAccuracies: [Double] = []
            var verticalAccuracies: [Double] = []

            for sample in routeData {
                coordinates.append([sample.longitude, sample.latitude, sample.altitude])
                timestamps.append(sample.timestamp)
                speeds.append(sample.speed)
                directions.append(sample.direction)
                horizontalAccuracies.append(sample.horizontalAccuracy)
                verticalAccuracies.append(sample.verticalAccuracy)
            }

            let lineString = GeoJSONFeature(
                geometry: GeoJSONGeometry(
                    type: "LineString",
                    coordinates: .lineString(coordinates)
                ),
                properties: GeoJSONProperties(
                    timestamps: timestamps,
                    speeds: speeds,
                    directions: directions,
                    horizontalAccuracies: horizontalAccuracies,
                    verticalAccuracies: verticalAccuracies
                )
            )
            features.append(lineString)
        }

        for waypoint in waypoints {
            let point = GeoJSONFeature(
                geometry: GeoJSONGeometry(
                    type: "Point",
                    coordinates: .point([waypoint.longitude, waypoint.latitude])
                ),
                properties: GeoJSONProperties(
                    markerType: "waypoint",
                    label: waypoint.label,
                    icon: waypoint.icon,
                    timestamp: waypoint.timestamp
                )
            )
            features.append(point)
        }

        return GeoJSONFeatureCollection(features: features)
    }

    // MARK: - Events

    static func convertEvents(events: [EventInterface]) -> [PilgrimEvent] {
        events.compactMap { event in
            guard let id = event.uuid else { return nil }
            return PilgrimEvent(
                id: id,
                title: event.title,
                comment: event.comment,
                startDate: event.startDate,
                endDate: event.endDate,
                walkIds: event.workouts.compactMap { $0.uuid }
            )
        }
    }

    // MARK: - Celestial

    private static func buildReflection(date: Date, system: ZodiacSystem) -> PilgrimReflection {
        let snapshot = CelestialCalculator.snapshot(for: date, system: system)
        let lunar = LunarPhase.current(date: date)

        let activePosition: (PlanetaryPosition) -> ZodiacPosition = { pos in
            system == .tropical ? pos.tropical : pos.sidereal
        }

        let positions = snapshot.positions.map { pos in
            let zodiac = activePosition(pos)
            return PilgrimPlanetaryPosition(
                planet: pos.planet.name.lowercased(),
                sign: zodiac.sign.name.lowercased(),
                degree: zodiac.degree,
                isRetrograde: pos.isRetrograde
            )
        }

        let elementCounts = snapshot.elementBalance.counts
        let celestial = PilgrimCelestialContext(
            lunarPhase: PilgrimLunarPhase(
                name: lunar.name,
                illumination: lunar.illumination,
                age: lunar.age,
                isWaxing: lunar.isWaxing
            ),
            planetaryPositions: positions,
            planetaryHour: PilgrimPlanetaryHour(
                planet: snapshot.planetaryHour.planet.name.lowercased(),
                planetaryDay: snapshot.planetaryHour.planetaryDay.name.lowercased()
            ),
            elementBalance: PilgrimElementBalance(
                fire: elementCounts[.fire] ?? 0,
                earth: elementCounts[.earth] ?? 0,
                air: elementCounts[.air] ?? 0,
                water: elementCounts[.water] ?? 0,
                dominant: snapshot.elementBalance.dominant?.rawValue
            ),
            seasonalMarker: snapshot.seasonalMarker?.rawValue,
            zodiacSystem: system.rawValue
        )

        return PilgrimReflection(style: nil, text: nil, celestialContext: celestial)
    }

    // MARK: - Manifest

    static func buildManifest(walkCount: Int, events: [PilgrimEvent]) -> PilgrimManifest {
        let formatter = MeasurementFormatter()
        let distanceUnit = formatter.string(from: UserPreferences.distanceMeasurementType.safeValue)
        let altitudeUnit = formatter.string(from: UserPreferences.altitudeMeasurementType.safeValue)
        let speedUnit = formatter.string(from: UserPreferences.speedMeasurementType.safeValue)
        let energyUnit = formatter.string(from: UserPreferences.energyMeasurementType.safeValue)

        let preferences = PilgrimPreferences(
            distanceUnit: distanceUnit,
            altitudeUnit: altitudeUnit,
            speedUnit: speedUnit,
            energyUnit: energyUnit,
            celestialAwareness: UserPreferences.celestialAwarenessEnabled.value,
            zodiacSystem: UserPreferences.zodiacSystem.value,
            beginWithIntention: UserPreferences.beginWithIntention.value
        )

        let promptStore = CustomPromptStyleStore()
        let customStyles = promptStore.styles.map { style in
            PilgrimCustomPromptStyle(
                id: style.id,
                title: style.title,
                icon: style.icon,
                instruction: style.instruction
            )
        }

        let intentionStore = IntentionHistoryStore()

        return PilgrimManifest(
            schemaVersion: schemaVersion,
            exportDate: Date(),
            appVersion: Config.version,
            walkCount: walkCount,
            preferences: preferences,
            customPromptStyles: customStyles,
            intentions: intentionStore.intentions,
            events: events
        )
    }

    // MARK: - Reverse Conversion (Import)

    static func convertToTemp(walk: PilgrimWalk) -> TempWalk {
        let walkType: Walk.WalkType = walk.type == "walking" ? .walking : .unknown
        let (routeData, waypoints) = convertRouteData(from: walk)
        let related = convertRelatedData(from: walk)
        let dayIdentifier = CustomDateFormatting.dayIdentifier(forDate: walk.startDate)

        return TempWalk(
            uuid: walk.id,
            workoutType: walkType,
            distance: walk.stats.distance,
            steps: walk.stats.steps,
            startDate: walk.startDate,
            endDate: walk.endDate,
            burnedEnergy: walk.stats.burnedEnergy,
            isRace: walk.isRace,
            comment: walk.intention,
            isUserModified: walk.isUserModified,
            healthKitUUID: nil,
            finishedRecording: walk.finishedRecording,
            ascend: walk.stats.ascent,
            descend: walk.stats.descent,
            activeDuration: walk.stats.activeDuration,
            pauseDuration: walk.stats.pauseDuration,
            dayIdentifier: dayIdentifier,
            talkDuration: walk.stats.talkDuration,
            meditateDuration: walk.stats.meditateDuration,
            heartRates: related.heartRates,
            routeData: routeData,
            pauses: related.pauses,
            workoutEvents: related.workoutEvents,
            voiceRecordings: related.voiceRecordings,
            activityIntervals: related.activities,
            favicon: walk.favicon,
            waypoints: waypoints,
            walkPhotos: PilgrimPackagePhotoConverter.importPhotos(from: walk.photos),
            weatherCondition: walk.weather?.condition,
            weatherTemperature: walk.weather?.temperature,
            weatherHumidity: walk.weather?.humidity,
            weatherWindSpeed: walk.weather?.windSpeed
        )
    }

    private static func convertRouteData(from walk: PilgrimWalk) -> ([TempRouteDataSample], [TempWaypoint]) {
        var routeData: [TempRouteDataSample] = []
        var waypoints: [TempWaypoint] = []

        for feature in walk.route.features {
            switch feature.geometry.type {
            case "LineString":
                if case .lineString(let coords) = feature.geometry.coordinates {
                    let timestamps = feature.properties.timestamps ?? []
                    let speeds = feature.properties.speeds ?? []
                    let dirs = feature.properties.directions ?? []
                    let hAccuracies = feature.properties.horizontalAccuracies ?? []
                    let vAccuracies = feature.properties.verticalAccuracies ?? []

                    for (index, coord) in coords.enumerated() {
                        let longitude = coord.count > 0 ? coord[0] : 0
                        let latitude = coord.count > 1 ? coord[1] : 0
                        let altitude = coord.count > 2 ? coord[2] : 0

                        routeData.append(TempRouteDataSample(
                            uuid: UUID(),
                            timestamp: index < timestamps.count ? timestamps[index] : walk.startDate,
                            latitude: latitude,
                            longitude: longitude,
                            altitude: altitude,
                            horizontalAccuracy: index < hAccuracies.count ? hAccuracies[index] : 0,
                            verticalAccuracy: index < vAccuracies.count ? vAccuracies[index] : 0,
                            speed: index < speeds.count ? speeds[index] : -1,
                            direction: index < dirs.count ? dirs[index] : -1
                        ))
                    }
                }
            case "Point":
                if case .point(let coord) = feature.geometry.coordinates {
                    let longitude = coord.count > 0 ? coord[0] : 0
                    let latitude = coord.count > 1 ? coord[1] : 0

                    waypoints.append(TempWaypoint(
                        uuid: UUID(),
                        latitude: latitude,
                        longitude: longitude,
                        label: feature.properties.label ?? "",
                        icon: feature.properties.icon ?? "",
                        timestamp: feature.properties.timestamp ?? walk.startDate
                    ))
                }
            default:
                break
            }
        }

        return (routeData, waypoints)
    }

    private static func convertRelatedData(from walk: PilgrimWalk) -> (
        pauses: [TempWalkPause],
        activities: [TempActivityInterval],
        voiceRecordings: [TempVoiceRecording],
        heartRates: [TempHeartRateDataSample],
        workoutEvents: [TempWalkEvent]
    ) {
        let pauses = walk.pauses.map { pause in
            TempWalkPause(
                uuid: UUID(),
                startDate: pause.startDate,
                endDate: pause.endDate,
                pauseType: pause.type == "automatic" ? .automatic : .manual
            )
        }

        let activities = walk.activities.map { activity in
            TempActivityInterval(
                uuid: UUID(),
                activityType: activity.type == "meditation" ? .meditation : .unknown,
                startDate: activity.startDate,
                endDate: activity.endDate
            )
        }

        let voiceRecordings = walk.voiceRecordings.map { recording in
            TempVoiceRecording(
                uuid: UUID(),
                startDate: recording.startDate,
                endDate: recording.endDate,
                duration: recording.duration,
                fileRelativePath: "",
                transcription: recording.transcription,
                wordsPerMinute: recording.wordsPerMinute,
                isEnhanced: recording.isEnhanced
            )
        }

        let heartRates = walk.heartRates.map { sample in
            TempHeartRateDataSample(
                uuid: UUID(),
                heartRate: sample.heartRate,
                timestamp: sample.timestamp
            )
        }

        let workoutEvents = walk.workoutEvents.map { event in
            TempWalkEvent(
                uuid: UUID(),
                eventType: walkEventType(from: event.type),
                timestamp: event.timestamp
            )
        }

        return (pauses, activities, voiceRecordings, heartRates, workoutEvents)
    }

    static func convertEvents(_ events: [PilgrimEvent]) -> [TempEvent] {
        events.map { event in
            TempEvent(
                uuid: event.id,
                title: event.title,
                comment: event.comment,
                startDate: event.startDate,
                endDate: event.endDate,
                workouts: event.walkIds
            )
        }
    }

    // MARK: - Helpers

    private static func workoutEventTypeString(_ type: WalkEvent.EventType) -> String {
        switch type {
        case .lap: return "lap"
        case .marker: return "marker"
        case .segment: return "segment"
        case .unknown: return "unknown"
        }
    }

    private static func walkEventType(from string: String) -> WalkEvent.EventType {
        switch string {
        case "lap": return .lap
        case "marker": return .marker
        case "segment": return .segment
        default: return .unknown
        }
    }
}
