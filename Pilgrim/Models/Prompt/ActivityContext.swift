import Foundation

struct ActivityContext {
    let recordings: [RecordingContext]
    let meditations: [MeditationContext]
    let duration: Double
    let distance: Double
    let startDate: Date
    let placeNames: [PlaceContext]
    let routeSpeeds: [Double]
    let recentWalkSnippets: [WalkSnippet]
    let intention: String?
    let waypoints: [WaypointContext]
    let weather: String?
    let lunarPhase: LunarPhase
    let celestial: CelestialSnapshot?

    var hasSpeech: Bool { !recordings.isEmpty }
}

extension ActivityContext {
    static func make(
        recordings: [RecordingContext] = [],
        meditations: [MeditationContext] = [],
        duration: Double = 1800,
        distance: Double = 2000,
        startDate: Date,
        placeNames: [PlaceContext] = [],
        routeSpeeds: [Double] = [],
        recentWalkSnippets: [WalkSnippet] = [],
        intention: String? = nil,
        waypoints: [WaypointContext] = [],
        weather: String? = nil,
        lunarPhase: LunarPhase? = nil,
        celestial: CelestialSnapshot? = nil
    ) -> ActivityContext {
        ActivityContext(
            recordings: recordings,
            meditations: meditations,
            duration: duration,
            distance: distance,
            startDate: startDate,
            placeNames: placeNames,
            routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets,
            intention: intention,
            waypoints: waypoints,
            weather: weather,
            lunarPhase: lunarPhase ?? LunarPhase.current(date: startDate),
            celestial: celestial
        )
    }
}
