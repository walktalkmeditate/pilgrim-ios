import Foundation

/// How the walk was undertaken — each mode carries its own ritual grammar,
/// explained to the downstream model by the practice lexicon.
enum PracticeMode {
    case wander
    case seek
    case honor
}

/// What this seek held: when each clearing was reached. An empty list is a
/// zero-arrival seek, which the lexicon honors rather than hides.
struct SeekStoryContext {
    let arrivalTimes: [Date]
}

/// What this honor held: whose Way was followed, and whether its end was
/// reached. The title is nil until a caller that can reach the Way store
/// fills it — the event stream alone does not carry it.
struct HonorStoryContext {
    let wayTitle: String?
    let arrived: Bool
}

/// Pure mapping from a walk's events to its practice context, mirroring how
/// SeekSummaryModel keeps event interpretation testable outside the view. A
/// `.seekMode` event marks the walk as a seek; `.seekArrival` events carry
/// when each clearing was reached. A `.honorMode` event marks an honor walk,
/// and `.honorArrival` says the end of the Way was reached.
enum WalkPracticeModel {

    static func practice(
        events: [(type: WalkEvent.EventType, timestamp: Date)]
    ) -> (mode: PracticeMode, seekStory: SeekStoryContext?, honorStory: HonorStoryContext?) {
        if events.contains(where: { $0.type == .honorMode }) {
            let arrived = events.contains { $0.type == .honorArrival }
            return (.honor, nil, HonorStoryContext(wayTitle: nil, arrived: arrived))
        }
        guard events.contains(where: { $0.type == .seekMode }) else {
            return (.wander, nil, nil)
        }
        let arrivals = events
            .filter { $0.type == .seekArrival }
            .map(\.timestamp)
            .sorted()
        return (.seek, SeekStoryContext(arrivalTimes: arrivals), nil)
    }
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
    let honorStory: HonorStoryContext?
    let pauses: [PauseContext]
    let ascent: Double?
    let descent: Double?
    var threadsDossier: String?

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
        honorStory: HonorStoryContext? = nil,
        pauses: [PauseContext] = [],
        ascent: Double? = nil,
        descent: Double? = nil,
        threadsDossier: String? = nil
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
            honorStory: honorStory,
            pauses: pauses,
            ascent: ascent,
            descent: descent,
            threadsDossier: threadsDossier
        )
    }
}
