import Foundation

// MARK: - Date Coding

enum PilgrimDateCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

// MARK: - Manifest

struct PilgrimManifest: Codable {
    let schemaVersion: String
    let exportDate: Date
    let appVersion: String
    let walkCount: Int
    let preferences: PilgrimPreferences
    let customPromptStyles: [PilgrimCustomPromptStyle]
    let intentions: [String]
    let events: [PilgrimEvent]
}

struct PilgrimPreferences: Codable {
    let distanceUnit: String
    let altitudeUnit: String
    let speedUnit: String
    let energyUnit: String
    let celestialAwareness: Bool
    let zodiacSystem: String
    let beginWithIntention: Bool
}

struct PilgrimCustomPromptStyle: Codable {
    let id: UUID
    let title: String
    let icon: String
    let instruction: String
}

struct PilgrimEvent: Codable {
    let id: UUID
    let title: String
    let comment: String?
    let startDate: Date?
    let endDate: Date?
    let walkIds: [UUID]
}

// MARK: - Walk

struct PilgrimWalk: Codable {
    let schemaVersion: String
    let id: UUID
    let type: String
    let startDate: Date
    let endDate: Date
    let stats: PilgrimStats
    let weather: PilgrimWeather?
    let route: GeoJSONFeatureCollection
    let pauses: [PilgrimPause]
    let activities: [PilgrimActivity]
    let voiceRecordings: [PilgrimVoiceRecording]
    let intention: String?
    let reflection: PilgrimReflection?
    let heartRates: [PilgrimHeartRate]
    let workoutEvents: [PilgrimWorkoutEvent]
    let favicon: String?
    let isRace: Bool
    let isUserModified: Bool
    let finishedRecording: Bool
    /// Photos pinned to this walk, populated only when the user opts in at
    /// export time. `nil` means "opted out" (or pre-reliquary `.pilgrim`
    /// format) — the JSON key is omitted entirely so byte-equality with the
    /// old format is preserved. An empty array means "opted in, no pinned
    /// photos".
    ///
    /// Declared as `var` (the only mutable property on `PilgrimWalk`) so the
    /// builder can populate each `PilgrimPhoto.embeddedPhotoFilename` after
    /// it successfully writes photo bytes into the archive's `photos/`
    /// directory. The converter produces walks with `embeddedPhotoFilename
    /// == nil`; the builder runs `PilgrimPhotoEmbedder.embedPhotos` then
    /// rewrites the array in place.
    var photos: [PilgrimPhoto]?
}

struct PilgrimStats: Codable {
    let distance: Double
    let steps: Int?
    let activeDuration: Double
    let pauseDuration: Double
    let ascent: Double
    let descent: Double
    let burnedEnergy: Double?
    let talkDuration: Double
    let meditateDuration: Double
}

struct PilgrimWeather: Codable {
    let temperature: Double
    let condition: String
    let humidity: Double?
    let windSpeed: Double?
}

// MARK: - GeoJSON

struct GeoJSONFeatureCollection: Codable {
    let type: String
    let features: [GeoJSONFeature]

    init(features: [GeoJSONFeature]) {
        self.type = "FeatureCollection"
        self.features = features
    }
}

struct GeoJSONFeature: Codable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: GeoJSONProperties

    init(geometry: GeoJSONGeometry, properties: GeoJSONProperties) {
        self.type = "Feature"
        self.geometry = geometry
        self.properties = properties
    }
}

struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: AnyCodableCoordinates
}

enum AnyCodableCoordinates: Codable {
    case point([Double])
    case lineString([[Double]])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .point(let coords):
            try container.encode(coords)
        case .lineString(let coords):
            try container.encode(coords)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let lineString = try? container.decode([[Double]].self) {
            self = .lineString(lineString)
        } else if let point = try? container.decode([Double].self) {
            self = .point(point)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Coordinates must be [Double] or [[Double]]"
            )
        }
    }
}

struct GeoJSONProperties: Codable {
    let timestamps: [Date]?
    let speeds: [Double]?
    let directions: [Double]?
    let horizontalAccuracies: [Double]?
    let verticalAccuracies: [Double]?

    let markerType: String?
    let label: String?
    let icon: String?
    let timestamp: Date?

    init(
        timestamps: [Date]? = nil,
        speeds: [Double]? = nil,
        directions: [Double]? = nil,
        horizontalAccuracies: [Double]? = nil,
        verticalAccuracies: [Double]? = nil,
        markerType: String? = nil,
        label: String? = nil,
        icon: String? = nil,
        timestamp: Date? = nil
    ) {
        self.timestamps = timestamps
        self.speeds = speeds
        self.directions = directions
        self.horizontalAccuracies = horizontalAccuracies
        self.verticalAccuracies = verticalAccuracies
        self.markerType = markerType
        self.label = label
        self.icon = icon
        self.timestamp = timestamp
    }
}

// MARK: - Pauses & Activities

struct PilgrimPause: Codable {
    let startDate: Date
    let endDate: Date
    let type: String
}

struct PilgrimActivity: Codable {
    let type: String
    let startDate: Date
    let endDate: Date
}

// MARK: - Voice Recordings

struct PilgrimVoiceRecording: Codable {
    let startDate: Date
    let endDate: Date
    let duration: Double
    let transcription: String?
    let wordsPerMinute: Double?
    let isEnhanced: Bool
}

// MARK: - Heart Rate

struct PilgrimHeartRate: Codable {
    let timestamp: Date
    let heartRate: Int
}

// MARK: - Photo

/// A walk photo the user pinned to the reliquary. Only written to the export
/// when the user opts in at export time. `embeddedPhotoFilename` is the name
/// of the file under `photos/` in the ZIP archive — nil if the photo bytes
/// are absent (e.g. the source PHAsset could not be resolved at export time).
struct PilgrimPhoto: Codable {
    let localIdentifier: String
    let capturedAt: Date
    let capturedLat: Double
    let capturedLng: Double
    let keptAt: Date
    let embeddedPhotoFilename: String?
    /// Base64 data URL for the JS bridge (in-app "My Journey"
    /// viewer). Nil in normal .pilgrim exports — the key is omitted
    /// from JSON so the file stays byte-identical to the archive
    /// format. Only populated by JourneyViewerView when building
    /// the loadData payload.
    let inlineUrl: String?

    init(
        localIdentifier: String,
        capturedAt: Date,
        capturedLat: Double,
        capturedLng: Double,
        keptAt: Date,
        embeddedPhotoFilename: String?,
        inlineUrl: String? = nil
    ) {
        self.localIdentifier = localIdentifier
        self.capturedAt = capturedAt
        self.capturedLat = capturedLat
        self.capturedLng = capturedLng
        self.keptAt = keptAt
        self.embeddedPhotoFilename = embeddedPhotoFilename
        self.inlineUrl = inlineUrl
    }
}

// MARK: - Workout Events

struct PilgrimWorkoutEvent: Codable {
    let timestamp: Date
    let type: String
}

// MARK: - Reflection & Celestial

struct PilgrimReflection: Codable {
    let style: String?
    let text: String?
    let celestialContext: PilgrimCelestialContext?
}

struct PilgrimCelestialContext: Codable {
    let lunarPhase: PilgrimLunarPhase
    let planetaryPositions: [PilgrimPlanetaryPosition]
    let planetaryHour: PilgrimPlanetaryHour
    let elementBalance: PilgrimElementBalance
    let seasonalMarker: String?
    let zodiacSystem: String
}

struct PilgrimLunarPhase: Codable {
    let name: String
    let illumination: Double
    let age: Double
    let isWaxing: Bool
}

struct PilgrimPlanetaryPosition: Codable {
    let planet: String
    let sign: String
    let degree: Double
    let isRetrograde: Bool
}

struct PilgrimPlanetaryHour: Codable {
    let planet: String
    let planetaryDay: String
}

struct PilgrimElementBalance: Codable {
    let fire: Int
    let earth: Int
    let air: Int
    let water: Int
    let dominant: String?
}
