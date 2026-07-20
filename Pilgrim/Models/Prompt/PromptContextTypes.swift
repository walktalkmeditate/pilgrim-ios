import Foundation

struct RecordingContext {
    let text: String
    let timestamp: Date
    let startCoordinate: (lat: Double, lon: Double)?
    let endCoordinate: (lat: Double, lon: Double)?
    let wordsPerMinute: Double?
}

struct MeditationContext {
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
}

enum PlaceRole { case start, end }

struct PlaceContext {
    let name: String
    let coordinate: (lat: Double, lon: Double)
    let role: PlaceRole
}

struct WalkSnippet {
    let date: Date
    let placeName: String?
    let transcriptionPreview: String
    var weatherCondition: String?
    var celestialSummary: String?

    init(
        date: Date,
        placeName: String?,
        transcriptionPreview: String,
        weatherCondition: String? = nil,
        celestialSummary: String? = nil
    ) {
        self.date = date
        self.placeName = placeName
        self.transcriptionPreview = transcriptionPreview
        self.weatherCondition = weatherCondition
        self.celestialSummary = celestialSummary
    }
}

struct PauseContext {
    let startDate: Date
    let duration: TimeInterval
}

struct WaypointContext {
    let label: String
    let icon: String
    let timestamp: Date
    let coordinate: (lat: Double, lon: Double)
}

struct PhotoContextEntry {
    let index: Int
    let distanceIntoWalk: String
    let time: String
    let coordinate: (lat: Double, lon: Double)
    let context: PhotoContext
}
