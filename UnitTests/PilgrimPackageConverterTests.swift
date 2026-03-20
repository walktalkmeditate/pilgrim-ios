import XCTest
@testable import Pilgrim

final class PilgrimPackageConverterTests: XCTestCase {

    // MARK: - Forward Conversion (Walk -> PilgrimWalk)

    func testConvert_basicFields() {
        let walk = makeTestWalk()
        let result = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)

        XCTAssertNotNil(result)
        guard let pw = result else { return }

        XCTAssertEqual(pw.schemaVersion, "1.0")
        XCTAssertEqual(pw.id, walk.uuid)
        XCTAssertEqual(pw.type, "walking")
        XCTAssertEqual(pw.startDate, walk.startDate)
        XCTAssertEqual(pw.endDate, walk.endDate)
        XCTAssertEqual(pw.intention, "Be present")
    }

    func testConvert_stats() {
        let walk = makeTestWalk()
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.stats.distance, 5000.0, accuracy: 0.01)
        XCTAssertEqual(pw.stats.steps, 6500)
        XCTAssertEqual(pw.stats.activeDuration, 3600.0, accuracy: 0.01)
        XCTAssertEqual(pw.stats.pauseDuration, 120.0, accuracy: 0.01)
        XCTAssertEqual(pw.stats.ascent, 50.0, accuracy: 0.01)
        XCTAssertEqual(pw.stats.descent, 45.0, accuracy: 0.01)
        XCTAssertEqual(pw.stats.burnedEnergy, 250.0)
        XCTAssertEqual(pw.stats.talkDuration, 180.0, accuracy: 0.01)
        XCTAssertEqual(pw.stats.meditateDuration, 300.0, accuracy: 0.01)
    }

    func testConvert_weather() {
        let walk = makeTestWalk(
            weatherCondition: "clear",
            weatherTemperature: 22.5,
            weatherHumidity: 0.6,
            weatherWindSpeed: 3.1
        )
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertNotNil(pw.weather)
        XCTAssertEqual(pw.weather?.temperature, 22.5)
        XCTAssertEqual(pw.weather?.condition, "clear")
        XCTAssertEqual(pw.weather?.humidity, 0.6)
        XCTAssertEqual(pw.weather?.windSpeed, 3.1)
    }

    func testConvert_nilWeather_whenNoTemperature() {
        let walk = makeTestWalk(weatherCondition: nil, weatherTemperature: nil)
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertNil(pw.weather)
    }

    func testConvert_nilWeather_whenNoCondition() {
        let walk = makeTestWalk(weatherCondition: nil, weatherTemperature: 20.0)
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertNil(pw.weather)
    }

    func testConvert_returnsNil_whenNoUUID() {
        let walk = makeTestWalk(uuid: nil)
        let result = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)

        XCTAssertNil(result)
    }

    func testConvert_preservesMetadataFlags() {
        let walk = makeTestWalk(isRace: true, isUserModified: true, finishedRecording: false, favicon: "flame")
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertTrue(pw.isRace)
        XCTAssertTrue(pw.isUserModified)
        XCTAssertFalse(pw.finishedRecording)
        XCTAssertEqual(pw.favicon, "flame")
    }

    // MARK: - GeoJSON Coordinate Order

    func testConvert_geoJSON_coordinateOrder_isLonLatAlt() {
        let routeSample = TempRouteDataSample(
            uuid: UUID(),
            timestamp: Date(),
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 15.5,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            speed: 1.4,
            direction: 270.0
        )
        let walk = makeTestWalk(routeData: [routeSample])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        let lineString = pw.route.features.first!
        if case .lineString(let coords) = lineString.geometry.coordinates {
            XCTAssertEqual(coords[0][0], -122.4194, accuracy: 0.0001, "First element must be longitude")
            XCTAssertEqual(coords[0][1], 37.7749, accuracy: 0.0001, "Second element must be latitude")
            XCTAssertEqual(coords[0][2], 15.5, accuracy: 0.01, "Third element must be altitude")
        } else {
            XCTFail("Expected lineString")
        }
    }

    func testConvert_geoJSON_directions_exported() {
        let routeSample = TempRouteDataSample(
            uuid: UUID(), timestamp: Date(),
            latitude: 37.0, longitude: -122.0, altitude: 0,
            horizontalAccuracy: 5.0, verticalAccuracy: 3.0,
            speed: 1.0, direction: 180.5
        )
        let walk = makeTestWalk(routeData: [routeSample])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.route.features[0].properties.directions?[0] ?? 0, 180.5, accuracy: 0.01)
    }

    func testConvert_geoJSON_waypoints() {
        let waypoint = TempWaypoint(
            uuid: UUID(),
            latitude: 40.7128,
            longitude: -74.0060,
            label: "Peaceful",
            icon: "leaf",
            timestamp: Date(timeIntervalSince1970: 2000)
        )
        let walk = makeTestWalk(waypoints: [waypoint])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        let pointFeature = pw.route.features.first!
        XCTAssertEqual(pointFeature.geometry.type, "Point")

        if case .point(let coords) = pointFeature.geometry.coordinates {
            XCTAssertEqual(coords[0], -74.0060, accuracy: 0.0001, "Waypoint longitude first")
            XCTAssertEqual(coords[1], 40.7128, accuracy: 0.0001, "Waypoint latitude second")
        } else {
            XCTFail("Expected point")
        }

        XCTAssertEqual(pointFeature.properties.markerType, "waypoint")
        XCTAssertEqual(pointFeature.properties.label, "Peaceful")
        XCTAssertEqual(pointFeature.properties.icon, "leaf")
    }

    func testConvert_emptyRoute() {
        let walk = makeTestWalk(routeData: [], waypoints: [])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertTrue(pw.route.features.isEmpty)
    }

    // MARK: - Heart Rates

    func testConvert_heartRates() {
        let hr = TempHeartRateDataSample(uuid: UUID(), heartRate: 145, timestamp: Date(timeIntervalSince1970: 1500))
        let walk = makeTestWalk(heartRates: [hr])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.heartRates.count, 1)
        XCTAssertEqual(pw.heartRates[0].heartRate, 145)
    }

    // MARK: - Workout Events

    func testConvert_workoutEvents() {
        let event = TempWalkEvent(uuid: UUID(), eventType: .marker, timestamp: Date(timeIntervalSince1970: 1200))
        let walk = makeTestWalk(workoutEvents: [event])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.workoutEvents.count, 1)
        XCTAssertEqual(pw.workoutEvents[0].type, "marker")
    }

    // MARK: - Pauses & Activities

    func testConvert_pauses() {
        let pause = TempWalkPause(
            uuid: UUID(),
            startDate: Date(timeIntervalSince1970: 2000),
            endDate: Date(timeIntervalSince1970: 2060),
            pauseType: .automatic
        )
        let walk = makeTestWalk(pauses: [pause])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.pauses.count, 1)
        XCTAssertEqual(pw.pauses[0].type, "automatic")
    }

    func testConvert_activities() {
        let activity = TempActivityInterval(
            uuid: UUID(),
            activityType: .meditation,
            startDate: Date(timeIntervalSince1970: 3000),
            endDate: Date(timeIntervalSince1970: 3300)
        )
        let walk = makeTestWalk(activityIntervals: [activity])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.activities.count, 1)
        XCTAssertEqual(pw.activities[0].type, "meditation")
    }

    // MARK: - Voice Recordings

    func testConvert_voiceRecordings() {
        let recording = TempVoiceRecording(
            uuid: UUID(),
            startDate: Date(timeIntervalSince1970: 1500),
            endDate: Date(timeIntervalSince1970: 1545),
            duration: 45.0,
            fileRelativePath: "Recordings/abc/rec.m4a",
            transcription: "The trail opens up",
            wordsPerMinute: 120.0,
            isEnhanced: true
        )
        let walk = makeTestWalk(voiceRecordings: [recording])
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertEqual(pw.voiceRecordings.count, 1)
        XCTAssertEqual(pw.voiceRecordings[0].transcription, "The trail opens up")
        XCTAssertEqual(pw.voiceRecordings[0].wordsPerMinute, 120.0)
        XCTAssertTrue(pw.voiceRecordings[0].isEnhanced)
        XCTAssertEqual(pw.voiceRecordings[0].duration, 45.0, accuracy: 0.01)
    }

    // MARK: - Celestial

    func testConvert_celestialEnabled_producesReflection() {
        let walk = makeTestWalk()
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: true)!

        XCTAssertNotNil(pw.reflection)
        XCTAssertNotNil(pw.reflection?.celestialContext)
        XCTAssertEqual(pw.reflection?.celestialContext?.planetaryPositions.count, 7)
        XCTAssertEqual(pw.reflection?.celestialContext?.zodiacSystem, "tropical")
    }

    func testConvert_celestialDisabled_nilReflection() {
        let walk = makeTestWalk()
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .tropical, celestialEnabled: false)!

        XCTAssertNil(pw.reflection)
    }

    func testConvert_sidereal_systemReflectedInContext() {
        let walk = makeTestWalk()
        let pw = PilgrimPackageConverter.convert(walk: walk, system: .sidereal, celestialEnabled: true)!

        XCTAssertEqual(pw.reflection?.celestialContext?.zodiacSystem, "sidereal")
    }

    // MARK: - Round Trip (Export then Import)

    func testRoundTrip_coreFields() {
        let (original, restored) = makeRoundTripPair()

        XCTAssertEqual(restored.uuid, original.uuid)
        XCTAssertEqual(restored.workoutType, .walking)
        XCTAssertEqual(restored.distance, 5000.0, accuracy: 0.01)
        XCTAssertEqual(restored.steps, 6500)
        XCTAssertEqual(restored.startDate.timeIntervalSince1970, original.startDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.endDate.timeIntervalSince1970, original.endDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.burnedEnergy, 250.0)
        XCTAssertTrue(restored.isRace)
        XCTAssertEqual(restored.comment, "Be present")
        XCTAssertTrue(restored.isUserModified)
        XCTAssertTrue(restored.finishedRecording)
        XCTAssertEqual(restored.ascend, 50.0, accuracy: 0.01)
        XCTAssertEqual(restored.descend, 45.0, accuracy: 0.01)
        XCTAssertEqual(restored.activeDuration, 3600.0, accuracy: 0.01)
        XCTAssertEqual(restored.pauseDuration, 120.0, accuracy: 0.01)
        XCTAssertEqual(restored.talkDuration, 180.0, accuracy: 0.01)
        XCTAssertEqual(restored.meditateDuration, 300.0, accuracy: 0.01)
        XCTAssertEqual(restored.favicon, "flame")
    }

    func testRoundTrip_weather() {
        let (_, restored) = makeRoundTripPair()

        XCTAssertEqual(restored.weatherCondition, "clear")
        XCTAssertEqual(restored.weatherTemperature, 22.5)
        XCTAssertEqual(restored.weatherHumidity, 0.6)
        XCTAssertEqual(restored.weatherWindSpeed, 3.1)
    }

    func testRoundTrip_routeData() {
        let (_, restored) = makeRoundTripPair()

        XCTAssertEqual(restored.routeData.count, 1)
        let sample = restored.routeData[0]
        XCTAssertEqual(sample.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(sample.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(sample.altitude, 15.5, accuracy: 0.01)
        XCTAssertEqual(sample.speed, 1.4, accuracy: 0.01)
        XCTAssertEqual(sample.direction, 270.0, accuracy: 0.01)
        XCTAssertEqual(sample.horizontalAccuracy, 5.0, accuracy: 0.01)
    }

    func testRoundTrip_collections() {
        let (_, restored) = makeRoundTripPair()

        XCTAssertEqual(restored.pauses.count, 1)
        XCTAssertEqual(restored.pauses[0].pauseType, .manual)

        XCTAssertEqual(restored.heartRates.count, 1)
        XCTAssertEqual(restored.heartRates[0].heartRate, 142)

        XCTAssertEqual(restored.workoutEvents.count, 1)
        XCTAssertEqual(restored.workoutEvents[0].eventType, .lap)

        XCTAssertEqual(restored.activityIntervals.count, 1)
        XCTAssertEqual(restored.activityIntervals[0].activityType, .meditation)

        XCTAssertEqual(restored.voiceRecordings.count, 1)
        XCTAssertEqual(restored.voiceRecordings[0].transcription, "Hello trail")
        XCTAssertEqual(restored.voiceRecordings[0].wordsPerMinute, 100.0)
        XCTAssertTrue(restored.voiceRecordings[0].isEnhanced)

        XCTAssertEqual(restored.waypoints.count, 1)
        XCTAssertEqual(restored.waypoints[0].label, "Oak")
        XCTAssertEqual(restored.waypoints[0].latitude, 37.78, accuracy: 0.001)
        XCTAssertEqual(restored.waypoints[0].longitude, -122.41, accuracy: 0.001)
    }

    // MARK: - Events

    func testConvertEvents_roundTrip() {
        let walkId = UUID()
        let eventId = UUID()
        let pilgrimEvents = [
            PilgrimEvent(
                id: eventId,
                title: "Camino Day 1",
                comment: "Beautiful start",
                startDate: Date(timeIntervalSince1970: 1000),
                endDate: Date(timeIntervalSince1970: 5000),
                walkIds: [walkId]
            )
        ]

        let tempEvents = PilgrimPackageConverter.convertEvents(pilgrimEvents)

        XCTAssertEqual(tempEvents.count, 1)
        XCTAssertEqual(tempEvents[0].uuid, eventId)
        XCTAssertEqual(tempEvents[0].title, "Camino Day 1")
        XCTAssertEqual(tempEvents[0].comment, "Beautiful start")
        XCTAssertEqual(tempEvents[0].workouts.count, 1)
    }

    // MARK: - Helpers

    private func makeRoundTripPair() -> (original: TempWalk, restored: TempWalk) {
        let start = Date(timeIntervalSince1970: 1710000000.456)
        let end = Date(timeIntervalSince1970: 1710003600.789)

        let original = makeTestWalk(
            routeData: [TempRouteDataSample(
                uuid: UUID(), timestamp: start,
                latitude: 37.7749, longitude: -122.4194, altitude: 15.5,
                horizontalAccuracy: 5.0, verticalAccuracy: 3.0,
                speed: 1.4, direction: 270.0
            )],
            pauses: [TempWalkPause(
                uuid: UUID(),
                startDate: Date(timeIntervalSince1970: 1710001800),
                endDate: Date(timeIntervalSince1970: 1710001860),
                pauseType: .manual
            )],
            workoutEvents: [TempWalkEvent(uuid: UUID(), eventType: .lap, timestamp: start)],
            voiceRecordings: [TempVoiceRecording(
                uuid: UUID(),
                startDate: start, endDate: Date(timeIntervalSince1970: 1710000045),
                duration: 45.0, fileRelativePath: "Recordings/a/b.m4a",
                transcription: "Hello trail", wordsPerMinute: 100.0, isEnhanced: true
            )],
            activityIntervals: [TempActivityInterval(
                uuid: UUID(), activityType: .meditation,
                startDate: Date(timeIntervalSince1970: 1710002000),
                endDate: Date(timeIntervalSince1970: 1710002300)
            )],
            heartRates: [TempHeartRateDataSample(uuid: UUID(), heartRate: 142, timestamp: start)],
            waypoints: [TempWaypoint(
                uuid: UUID(), latitude: 37.78, longitude: -122.41,
                label: "Oak", icon: "tree", timestamp: start
            )],
            isRace: true,
            isUserModified: true,
            favicon: "flame",
            weatherCondition: "clear",
            weatherTemperature: 22.5,
            weatherHumidity: 0.6,
            weatherWindSpeed: 3.1
        )

        var mutableOriginal = original
        mutableOriginal.startDate = start
        mutableOriginal.endDate = end

        let exported = PilgrimPackageConverter.convert(walk: mutableOriginal, system: .tropical, celestialEnabled: false)!
        let encoder = PilgrimDateCoding.makeEncoder()
        let decoder = PilgrimDateCoding.makeDecoder()
        let json = try! encoder.encode(exported)
        let reimported = try! decoder.decode(PilgrimWalk.self, from: json)
        let restored = PilgrimPackageConverter.convertToTemp(walk: reimported)

        return (mutableOriginal, restored)
    }

    private func makeTestWalk(
        uuid: UUID? = UUID(),
        routeData: [TempRouteDataSample] = [],
        pauses: [TempWalkPause] = [],
        workoutEvents: [TempWalkEvent] = [],
        voiceRecordings: [TempVoiceRecording] = [],
        activityIntervals: [TempActivityInterval] = [],
        heartRates: [TempHeartRateDataSample] = [],
        waypoints: [TempWaypoint] = [],
        isRace: Bool = false,
        isUserModified: Bool = false,
        finishedRecording: Bool = true,
        favicon: String? = nil,
        weatherCondition: String? = nil,
        weatherTemperature: Double? = nil,
        weatherHumidity: Double? = nil,
        weatherWindSpeed: Double? = nil
    ) -> TempWalk {
        TempWalk(
            uuid: uuid,
            workoutType: .walking,
            distance: 5000.0,
            steps: 6500,
            startDate: Date(timeIntervalSince1970: 1710000000),
            endDate: Date(timeIntervalSince1970: 1710003600),
            burnedEnergy: 250.0,
            isRace: isRace,
            comment: "Be present",
            isUserModified: isUserModified,
            healthKitUUID: nil,
            finishedRecording: finishedRecording,
            ascend: 50.0,
            descend: 45.0,
            activeDuration: 3600.0,
            pauseDuration: 120.0,
            dayIdentifier: "2024-03-09",
            talkDuration: 180.0,
            meditateDuration: 300.0,
            heartRates: heartRates,
            routeData: routeData,
            pauses: pauses,
            workoutEvents: workoutEvents,
            voiceRecordings: voiceRecordings,
            activityIntervals: activityIntervals,
            favicon: favicon,
            waypoints: waypoints,
            weatherCondition: weatherCondition,
            weatherTemperature: weatherTemperature,
            weatherHumidity: weatherHumidity,
            weatherWindSpeed: weatherWindSpeed
        )
    }
}
