import XCTest
@testable import Pilgrim

final class PilgrimPackageModelTests: XCTestCase {

    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        encoder = PilgrimDateCoding.makeEncoder()
        decoder = PilgrimDateCoding.makeDecoder()
    }

    // MARK: - Date Precision

    func testDate_subSecondPrecision_preserved() throws {
        let original = PilgrimPause(
            startDate: Date(timeIntervalSince1970: 1710000000.123),
            endDate: Date(timeIntervalSince1970: 1710000060.789),
            type: "manual"
        )

        let decoded = try roundTrip(original)
        XCTAssertEqual(
            decoded.startDate.timeIntervalSince1970,
            1710000000.123,
            accuracy: 0.001
        )
        XCTAssertEqual(
            decoded.endDate.timeIntervalSince1970,
            1710000060.789,
            accuracy: 0.001
        )
    }

    // MARK: - Stats

    func testStats_roundTrip() throws {
        let stats = PilgrimStats(
            distance: 5432.1,
            steps: 7200,
            activeDuration: 3600.0,
            pauseDuration: 120.0,
            ascent: 45.2,
            descent: 38.1,
            burnedEnergy: 320.5,
            talkDuration: 180.0,
            meditateDuration: 300.0
        )

        let decoded = try roundTrip(stats)
        XCTAssertEqual(decoded.distance, 5432.1, accuracy: 0.01)
        XCTAssertEqual(decoded.steps, 7200)
        XCTAssertEqual(decoded.activeDuration, 3600.0, accuracy: 0.01)
        XCTAssertEqual(decoded.burnedEnergy, 320.5)
    }

    func testStats_nilBurnedEnergy() throws {
        let stats = PilgrimStats(
            distance: 100, steps: nil, activeDuration: 60,
            pauseDuration: 0, ascent: 0, descent: 0,
            burnedEnergy: nil, talkDuration: 0, meditateDuration: 0
        )

        let decoded = try roundTrip(stats)
        XCTAssertNil(decoded.steps)
        XCTAssertNil(decoded.burnedEnergy)
    }

    // MARK: - Weather

    func testWeather_roundTrip() throws {
        let weather = PilgrimWeather(
            temperature: 18.5, condition: "partly_cloudy",
            humidity: 0.65, windSpeed: 3.2
        )

        let decoded = try roundTrip(weather)
        XCTAssertEqual(decoded.temperature, 18.5, accuracy: 0.01)
        XCTAssertEqual(decoded.condition, "partly_cloudy")
        XCTAssertEqual(decoded.humidity, 0.65)
        XCTAssertEqual(decoded.windSpeed, 3.2)
    }

    // MARK: - GeoJSON

    func testGeoJSON_lineString_roundTrip() throws {
        let feature = GeoJSONFeature(
            geometry: GeoJSONGeometry(
                type: "LineString",
                coordinates: .lineString([[-122.42, 37.78, 15.2], [-122.41, 37.79, 16.0]])
            ),
            properties: GeoJSONProperties(
                timestamps: [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 1060)],
                speeds: [1.2, 1.5],
                directions: [45.0, 90.0],
                horizontalAccuracies: [5.0, 4.5],
                verticalAccuracies: [3.0, 2.8]
            )
        )

        let collection = GeoJSONFeatureCollection(features: [feature])
        let decoded = try roundTrip(collection)

        XCTAssertEqual(decoded.type, "FeatureCollection")
        XCTAssertEqual(decoded.features.count, 1)

        let f = decoded.features[0]
        if case .lineString(let coords) = f.geometry.coordinates {
            XCTAssertEqual(coords.count, 2)
            XCTAssertEqual(coords[0][0], -122.42, accuracy: 0.001)
            XCTAssertEqual(coords[0][1], 37.78, accuracy: 0.001)
        } else {
            XCTFail("Expected lineString coordinates")
        }

        XCTAssertEqual(f.properties.directions?.count, 2)
        XCTAssertEqual(f.properties.directions?[0] ?? 0, 45.0, accuracy: 0.01)
    }

    func testGeoJSON_point_roundTrip() throws {
        let feature = GeoJSONFeature(
            geometry: GeoJSONGeometry(
                type: "Point",
                coordinates: .point([-122.41, 37.79])
            ),
            properties: GeoJSONProperties(
                markerType: "waypoint",
                label: "Ancient Oak",
                icon: "tree",
                timestamp: Date(timeIntervalSince1970: 1000)
            )
        )

        let decoded = try roundTrip(feature)

        if case .point(let coords) = decoded.geometry.coordinates {
            XCTAssertEqual(coords[0], -122.41, accuracy: 0.001)
            XCTAssertEqual(coords[1], 37.79, accuracy: 0.001)
        } else {
            XCTFail("Expected point coordinates")
        }

        XCTAssertEqual(decoded.properties.markerType, "waypoint")
        XCTAssertEqual(decoded.properties.label, "Ancient Oak")
    }

    func testGeoJSON_emptyCollection() throws {
        let collection = GeoJSONFeatureCollection(features: [])
        let decoded = try roundTrip(collection)
        XCTAssertTrue(decoded.features.isEmpty)
    }

    // MARK: - Heart Rate

    func testHeartRate_roundTrip() throws {
        let hr = PilgrimHeartRate(
            timestamp: Date(timeIntervalSince1970: 1000.5),
            heartRate: 142
        )

        let decoded = try roundTrip(hr)
        XCTAssertEqual(decoded.heartRate, 142)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1000.5, accuracy: 0.001)
    }

    // MARK: - Workout Event

    func testWorkoutEvent_roundTrip() throws {
        let event = PilgrimWorkoutEvent(
            timestamp: Date(timeIntervalSince1970: 2000),
            type: "marker"
        )

        let decoded = try roundTrip(event)
        XCTAssertEqual(decoded.type, "marker")
    }

    // MARK: - Event

    func testEvent_roundTrip() throws {
        let walkId1 = UUID()
        let walkId2 = UUID()
        let event = PilgrimEvent(
            id: UUID(),
            title: "Camino Day 1",
            comment: "First leg",
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 5000),
            walkIds: [walkId1, walkId2]
        )

        let decoded = try roundTrip(event)
        XCTAssertEqual(decoded.title, "Camino Day 1")
        XCTAssertEqual(decoded.comment, "First leg")
        XCTAssertEqual(decoded.walkIds.count, 2)
        XCTAssertEqual(decoded.walkIds[0], walkId1)
    }

    // MARK: - Celestial Context

    func testCelestialContext_roundTrip() throws {
        let context = PilgrimCelestialContext(
            lunarPhase: PilgrimLunarPhase(
                name: "Waxing Gibbous", illumination: 0.78, age: 10.3, isWaxing: true
            ),
            planetaryPositions: [
                PilgrimPlanetaryPosition(
                    planet: "sun", sign: "pisces", degree: 27.5, isRetrograde: false
                )
            ],
            planetaryHour: PilgrimPlanetaryHour(planet: "venus", planetaryDay: "mars"),
            elementBalance: PilgrimElementBalance(
                fire: 2, earth: 1, air: 3, water: 1, dominant: "air"
            ),
            seasonalMarker: "springEquinox",
            zodiacSystem: "tropical"
        )

        let decoded = try roundTrip(context)
        XCTAssertEqual(decoded.lunarPhase.name, "Waxing Gibbous")
        XCTAssertEqual(decoded.planetaryPositions.count, 1)
        XCTAssertEqual(decoded.elementBalance.dominant, "air")
    }

    // MARK: - Walk

    func testWalk_fullRoundTrip() throws {
        let walk = PilgrimWalk(
            schemaVersion: "1.0",
            id: UUID(),
            type: "walking",
            startDate: Date(timeIntervalSince1970: 1000.333),
            endDate: Date(timeIntervalSince1970: 4600.777),
            stats: PilgrimStats(
                distance: 5432.1, steps: 7200,
                activeDuration: 3600.0, pauseDuration: 120.0,
                ascent: 45.2, descent: 38.1,
                burnedEnergy: 320.5,
                talkDuration: 180.0, meditateDuration: 300.0
            ),
            weather: PilgrimWeather(
                temperature: 18.5, condition: "partly_cloudy",
                humidity: 0.65, windSpeed: 3.2
            ),
            route: GeoJSONFeatureCollection(features: []),
            pauses: [
                PilgrimPause(
                    startDate: Date(timeIntervalSince1970: 2000),
                    endDate: Date(timeIntervalSince1970: 2060),
                    type: "manual"
                )
            ],
            activities: [
                PilgrimActivity(
                    type: "meditation",
                    startDate: Date(timeIntervalSince1970: 3000),
                    endDate: Date(timeIntervalSince1970: 3300)
                )
            ],
            voiceRecordings: [],
            intention: "Walk with gratitude today",
            reflection: nil,
            heartRates: [PilgrimHeartRate(timestamp: Date(timeIntervalSince1970: 1500), heartRate: 85)],
            workoutEvents: [PilgrimWorkoutEvent(timestamp: Date(timeIntervalSince1970: 1200), type: "lap")],
            favicon: "flame",
            isRace: false,
            isUserModified: true,
            finishedRecording: true,
            photos: nil
        )

        let decoded = try roundTrip(walk)
        XCTAssertEqual(decoded.schemaVersion, "1.0")
        XCTAssertEqual(decoded.id, walk.id)
        XCTAssertEqual(decoded.startDate.timeIntervalSince1970, 1000.333, accuracy: 0.001)
        XCTAssertEqual(decoded.stats.distance, 5432.1, accuracy: 0.01)
        XCTAssertNotNil(decoded.weather)
        XCTAssertEqual(decoded.pauses.count, 1)
        XCTAssertEqual(decoded.activities.count, 1)
        XCTAssertEqual(decoded.intention, "Walk with gratitude today")
        XCTAssertEqual(decoded.heartRates.count, 1)
        XCTAssertEqual(decoded.heartRates[0].heartRate, 85)
        XCTAssertEqual(decoded.workoutEvents.count, 1)
        XCTAssertEqual(decoded.workoutEvents[0].type, "lap")
        XCTAssertEqual(decoded.favicon, "flame")
        XCTAssertFalse(decoded.isRace)
        XCTAssertTrue(decoded.isUserModified)
        XCTAssertTrue(decoded.finishedRecording)
    }

    func testWalk_nilWeather() throws {
        let walk = makeMinimalWalk(weather: nil)
        let decoded = try roundTrip(walk)
        XCTAssertNil(decoded.weather)
    }

    // MARK: - Manifest

    func testManifest_roundTrip() throws {
        let walkId = UUID()
        let manifest = PilgrimManifest(
            schemaVersion: "1.0",
            exportDate: Date(timeIntervalSince1970: 1000),
            appVersion: "2.1.0",
            walkCount: 47,
            preferences: PilgrimPreferences(
                distanceUnit: "km", altitudeUnit: "m",
                speedUnit: "min/km", energyUnit: "kcal",
                celestialAwareness: true,
                zodiacSystem: "tropical",
                beginWithIntention: true
            ),
            customPromptStyles: [
                PilgrimCustomPromptStyle(
                    id: UUID(), title: "Haiku Walker",
                    icon: "leaf", instruction: "Transform the walk into three haiku..."
                )
            ],
            intentions: ["Walk with gratitude today", "Listen to the wind"],
            events: [
                PilgrimEvent(
                    id: UUID(), title: "Camino", comment: nil,
                    startDate: Date(timeIntervalSince1970: 1000),
                    endDate: Date(timeIntervalSince1970: 5000),
                    walkIds: [walkId]
                )
            ]
        )

        let decoded = try roundTrip(manifest)
        XCTAssertEqual(decoded.schemaVersion, "1.0")
        XCTAssertEqual(decoded.walkCount, 47)
        XCTAssertEqual(decoded.customPromptStyles.count, 1)
        XCTAssertEqual(decoded.intentions.count, 2)
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.events[0].title, "Camino")
        XCTAssertEqual(decoded.events[0].walkIds, [walkId])
    }

    // MARK: - Helpers

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    private func makeMinimalWalk(weather: PilgrimWeather? = nil) -> PilgrimWalk {
        PilgrimWalk(
            schemaVersion: "1.0",
            id: UUID(),
            type: "walking",
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            stats: PilgrimStats(
                distance: 100, steps: nil,
                activeDuration: 60, pauseDuration: 0,
                ascent: 0, descent: 0,
                burnedEnergy: nil,
                talkDuration: 0, meditateDuration: 0
            ),
            weather: weather,
            route: GeoJSONFeatureCollection(features: []),
            pauses: [],
            activities: [],
            voiceRecordings: [],
            intention: nil,
            reflection: nil,
            heartRates: [],
            workoutEvents: [],
            favicon: nil,
            isRace: false,
            isUserModified: false,
            finishedRecording: true,
            photos: nil
        )
    }
}
