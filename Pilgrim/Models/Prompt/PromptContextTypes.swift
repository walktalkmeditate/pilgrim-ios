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
    var weatherCondition: String? = nil
    var celestialSummary: String? = nil
}

struct WaypointContext {
    let label: String
    let icon: String
    let timestamp: Date
    let coordinate: (lat: Double, lon: Double)
}
