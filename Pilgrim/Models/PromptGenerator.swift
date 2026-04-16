import Foundation

struct PromptGenerator {

    typealias RecordingContext = Pilgrim.RecordingContext
    typealias MeditationContext = Pilgrim.MeditationContext
    typealias PlaceRole = Pilgrim.PlaceRole
    typealias PlaceContext = Pilgrim.PlaceContext
    typealias WalkSnippet = Pilgrim.WalkSnippet
    typealias WaypointContext = Pilgrim.WaypointContext

    // MARK: - ActivityContext API

    static func generate(style: PromptStyle, context: ActivityContext) -> GeneratedPrompt {
        let text = PromptAssembler.assemble(context: context, voice: style.voice)
        return GeneratedPrompt(style: style, customStyle: nil, text: text)
    }

    static func generateCustom(customStyle: CustomPromptStyle, context: ActivityContext) -> GeneratedPrompt {
        let text = PromptAssembler.assemble(context: context, voice: customStyle)
        return GeneratedPrompt(style: nil, customStyle: customStyle, text: text)
    }

    static func generateAll(context: ActivityContext) -> [GeneratedPrompt] {
        PromptStyle.allCases.map { generate(style: $0, context: context) }
    }

    // MARK: - Legacy Parameter-Spreading API

    static func generate(
        style: PromptStyle,
        recordings: [RecordingContext],
        meditations: [MeditationContext],
        duration: Double,
        distance: Double,
        startDate: Date,
        placeNames: [PlaceContext] = [],
        routeSpeeds: [Double] = [],
        recentWalkSnippets: [WalkSnippet] = [],
        intention: String? = nil,
        waypoints: [WaypointContext] = [],
        weather: String? = nil
    ) -> GeneratedPrompt {
        let context = ActivityContext(
            recordings: recordings, meditations: meditations,
            duration: duration, distance: distance, startDate: startDate,
            placeNames: placeNames, routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets, intention: intention,
            waypoints: waypoints, weather: weather,
            lunarPhase: LunarPhase.current(date: startDate), celestial: nil,
            photoContexts: [], narrativeArc: nil
        )
        return generate(style: style, context: context)
    }

    static func generateCustom(
        customStyle: CustomPromptStyle,
        recordings: [RecordingContext],
        meditations: [MeditationContext],
        duration: Double,
        distance: Double,
        startDate: Date,
        placeNames: [PlaceContext] = [],
        routeSpeeds: [Double] = [],
        recentWalkSnippets: [WalkSnippet] = [],
        intention: String? = nil,
        waypoints: [WaypointContext] = [],
        weather: String? = nil
    ) -> GeneratedPrompt {
        let context = ActivityContext(
            recordings: recordings, meditations: meditations,
            duration: duration, distance: distance, startDate: startDate,
            placeNames: placeNames, routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets, intention: intention,
            waypoints: waypoints, weather: weather,
            lunarPhase: LunarPhase.current(date: startDate), celestial: nil,
            photoContexts: [], narrativeArc: nil
        )
        return generateCustom(customStyle: customStyle, context: context)
    }

    static func generateAll(
        recordings: [RecordingContext],
        meditations: [MeditationContext],
        duration: Double,
        distance: Double,
        startDate: Date,
        placeNames: [PlaceContext] = [],
        routeSpeeds: [Double] = [],
        recentWalkSnippets: [WalkSnippet] = [],
        intention: String? = nil,
        waypoints: [WaypointContext] = [],
        weather: String? = nil
    ) -> [GeneratedPrompt] {
        let context = ActivityContext(
            recordings: recordings, meditations: meditations,
            duration: duration, distance: distance, startDate: startDate,
            placeNames: placeNames, routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets, intention: intention,
            waypoints: waypoints, weather: weather,
            lunarPhase: LunarPhase.current(date: startDate), celestial: nil,
            photoContexts: [], narrativeArc: nil
        )
        return generateAll(context: context)
    }

    static func formatWeather(_ walk: WalkInterface) -> String? {
        ContextFormatter.formatWeather(walk)
    }
}

extension String {
    func truncatedAtWordBoundary(maxLength: Int = 200) -> String {
        guard count > maxLength else { return self }
        let truncated = prefix(maxLength)
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return String(truncated) + "..."
    }
}
