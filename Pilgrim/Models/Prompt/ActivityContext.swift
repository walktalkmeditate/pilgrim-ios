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

/// Pure mapping from a walk's events to its practice context, mirroring how
/// SeekSummaryModel keeps event interpretation testable outside the view. A
/// `.seekMode` event marks the walk as a seek; `.seekArrival` events carry
/// when each clearing was reached.
enum WalkPracticeModel {

    static func practice(
        events: [(type: WalkEvent.EventType, timestamp: Date)]
    ) -> (mode: PracticeMode, seekStory: SeekStoryContext?) {
        guard events.contains(where: { $0.type == .seekMode }) else {
            return (.wander, nil)
        }
        let arrivals = events
            .filter { $0.type == .seekArrival }
            .map(\.timestamp)
            .sorted()
        return (.seek, SeekStoryContext(arrivalTimes: arrivals))
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
    let pauses: [PauseContext]
    let ascent: Double?
    let descent: Double?
    var threadsDossier: String?
    /// Second pre-rendered variant, built in the same pass. Voices whose
    /// policy excludes marker lines read this one. Both are built once —
    /// `generateAll` fans one context across every style.
    var threadsDossierWithoutMarkers: String?
    /// Third pre-rendered variant, built in the same pass: just the
    /// `**Noticed:**` block (place resonance, moon, weather, climb, photo
    /// adjacency, speech shape — never markerColoring), with no marker
    /// section and no thread section at all. Voices whose policy excludes
    /// thread analysis entirely (Creative, Gratitude) read this one rather
    /// than losing the dossier's sensory content outright.
    var threadsDossierSensesOnly: String?
    /// The `Unchanged:` block, built once alongside the dossier and emitted
    /// only for voices whose context policy requests it. Built once because
    /// `PromptGenerator.generateAll` fans ONE context across every style —
    /// building per voice would undo PR #65's single-pass work.
    var unchangedBlock: String?

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
        descent: Double? = nil,
        threadsDossier: String? = nil,
        threadsDossierWithoutMarkers: String? = nil,
        threadsDossierSensesOnly: String? = nil,
        unchangedBlock: String? = nil
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
            descent: descent,
            threadsDossier: threadsDossier,
            threadsDossierWithoutMarkers: threadsDossierWithoutMarkers,
            threadsDossierSensesOnly: threadsDossierSensesOnly,
            unchangedBlock: unchangedBlock
        )
    }
}
