import Foundation

/// How the walk was undertaken — each mode carries its own ritual grammar,
/// explained to the downstream model by the practice lexicon.
enum PracticeMode {
    case wander
    case seek
}

/// What this seek held: when each clearing was reached. An empty list is a
/// zero-arrival seek, which the lexicon honors rather than hides.
struct SeekStoryContext {
    let arrivalTimes: [Date]
}

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
    let photoContexts: [PhotoContextEntry]
    let narrativeArc: NarrativeArc?
    let mode: PracticeMode
    let seekStory: SeekStoryContext?
    let pauses: [PauseContext]
    let ascent: Double?
    let descent: Double?

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
        celestial: CelestialSnapshot? = nil,
        photoContexts: [PhotoContextEntry] = [],
        narrativeArc: NarrativeArc? = nil,
        mode: PracticeMode = .wander,
        seekStory: SeekStoryContext? = nil,
        pauses: [PauseContext] = [],
        ascent: Double? = nil,
        descent: Double? = nil
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
            celestial: celestial,
            photoContexts: photoContexts,
            narrativeArc: narrativeArc,
            mode: mode,
            seekStory: seekStory,
            pauses: pauses,
            ascent: ascent,
            descent: descent
        )
    }
}
