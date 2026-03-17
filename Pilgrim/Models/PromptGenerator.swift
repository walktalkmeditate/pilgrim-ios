import Foundation

enum PromptStyle: String, CaseIterable, Identifiable {
    case contemplative
    case reflective
    case creative
    case gratitude
    case philosophical
    case journaling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contemplative: return "Contemplative"
        case .reflective: return "Reflective"
        case .creative: return "Creative"
        case .gratitude: return "Gratitude"
        case .philosophical: return "Philosophical"
        case .journaling: return "Journaling"
        }
    }

    var icon: String {
        switch self {
        case .contemplative: return "leaf.fill"
        case .reflective: return "eye.fill"
        case .creative: return "paintbrush.fill"
        case .gratitude: return "heart.fill"
        case .philosophical: return "books.vertical.fill"
        case .journaling: return "pencil.and.scribble"
        }
    }

    var description: String {
        switch self {
        case .contemplative: return "Sit with what emerged from movement"
        case .reflective: return "Identify patterns and emotional undercurrents"
        case .creative: return "Transform thoughts into poetry or metaphor"
        case .gratitude: return "Find thanksgiving in observations"
        case .philosophical: return "Explore deeper meaning and wisdom"
        case .journaling: return "Structure raw thoughts into a journal entry"
        }
    }
}

struct GeneratedPrompt: Identifiable {
    let id = UUID()
    let style: PromptStyle?
    let customStyle: CustomPromptStyle?
    let text: String

    var title: String { customStyle?.title ?? style?.title ?? "" }
    var icon: String { customStyle?.icon ?? style?.icon ?? "questionmark" }
    var subtitle: String { customStyle?.instruction ?? style?.description ?? "" }
}

struct PromptGenerator {

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
    }

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
        intention: String? = nil
    ) -> GeneratedPrompt {
        let combinedText = formatRecordings(recordings)
        let meditationText = formatMeditations(meditations)
        let metadata = formatMetadata(duration: duration, distance: distance, startDate: startDate)
        let location = formatPlaceNames(placeNames)
        let pace = formatPaceContext(speeds: routeSpeeds)
        let recentWalks = formatRecentWalks(recentWalkSnippets)

        let preamble: String
        let instruction: String

        switch style {
        case .contemplative:
            preamble = "During a walking meditation, these words arose naturally from the rhythm of movement and breath. They were not planned or curated — they emerged as the body moved through space."
            instruction = """
                Please receive these walking thoughts with gentleness. Help me sit with what emerged, without rushing to analyze or fix. What was my body and spirit trying to tell me through these words? What wants to be noticed, held, or simply acknowledged? Respond in a contemplative, unhurried tone.
                """

        case .reflective:
            preamble = "These are voice recordings captured during a walk, transcribed as spoken. They represent unfiltered thoughts, observations, and feelings that surfaced while moving."
            instruction = """
                Please analyze these walking reflections for patterns, recurring themes, and emotional undercurrents. What connections do you see between the different moments? What might I be processing or working through? What contradictions or tensions are present? Offer observations that help me understand myself better.
                """

        case .creative:
            preamble = "A walker spoke these words into the open air while moving through the world. They are raw material — fragments of observation, feeling, and thought gathered by a body in motion."
            instruction = """
                Transform these walking fragments into something creative. You might compose a poem, write a short prose piece, create a series of haiku, or craft a brief narrative. Let the rhythm of the walk inform the rhythm of the writing. Preserve the essence but elevate the expression.
                """

        case .gratitude:
            preamble = "These words were spoken during a walk — a time of moving through the world with awareness. Somewhere in these observations and thoughts are seeds of gratitude, even if not explicitly stated."
            instruction = """
                Help me find the gratitude woven through these walking thoughts. What am I thankful for, even if I didn't say it directly? What blessings are hiding in my observations? What can I appreciate about this moment in my life, this body that walks, this world I moved through? Frame your response as a practice of thanksgiving.
                """

        case .philosophical:
            preamble = "Walking has long been a companion to philosophical thought — from Aristotle's peripatetic school to Kierkegaard's daily constitutionals. These words emerged during such a walk, where movement and thought intertwined."
            instruction = """
                Engage with these walking thoughts philosophically. What deeper questions are being asked? What assumptions about life, meaning, or existence are being explored? Connect my observations to broader wisdom traditions, philosophical concepts, or universal human experiences. Help me think more deeply about what I was already beginning to think.
                """

        case .journaling:
            preamble = "The following are raw, unedited voice recordings from a walk. They capture thoughts as they occurred — scattered, honest, and in the moment."
            instruction = """
                Help me turn these scattered walking thoughts into a coherent journal entry. Organize the themes, add transitions between ideas, and create a narrative flow while preserving my authentic voice. The result should read as a thoughtful, personal journal entry that I could return to and understand. Include a brief summary of the walk's key themes at the end.
                """
        }

        let prompt = buildPrompt(
            preamble: preamble,
            instruction: instruction,
            transcription: combinedText,
            meditations: meditationText,
            metadata: metadata,
            location: location,
            pace: pace,
            recentWalks: recentWalks,
            intention: intention
        )
        return GeneratedPrompt(style: style, customStyle: nil, text: prompt)
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
        intention: String? = nil
    ) -> GeneratedPrompt {
        let combinedText = formatRecordings(recordings)
        let meditationText = formatMeditations(meditations)
        let metadata = formatMetadata(duration: duration, distance: distance, startDate: startDate)
        let location = formatPlaceNames(placeNames)
        let pace = formatPaceContext(speeds: routeSpeeds)
        let recentWalks = formatRecentWalks(recentWalkSnippets)

        let preamble = "These are voice recordings captured during a walk, transcribed as spoken. They represent unfiltered thoughts, observations, and feelings that surfaced while moving."

        let prompt = buildPrompt(
            preamble: preamble,
            instruction: customStyle.instruction,
            transcription: combinedText,
            meditations: meditationText,
            metadata: metadata,
            location: location,
            pace: pace,
            recentWalks: recentWalks,
            intention: intention
        )
        return GeneratedPrompt(style: nil, customStyle: customStyle, text: prompt)
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
        intention: String? = nil
    ) -> [GeneratedPrompt] {
        PromptStyle.allCases.map { style in
            generate(
                style: style,
                recordings: recordings,
                meditations: meditations,
                duration: duration,
                distance: distance,
                startDate: startDate,
                placeNames: placeNames,
                routeSpeeds: routeSpeeds,
                recentWalkSnippets: recentWalkSnippets,
                intention: intention
            )
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static func formatRecordings(_ recordings: [RecordingContext]) -> String {
        return recordings.map { item in
            var header = "[\(timeFormatter.string(from: item.timestamp))]"
            if let start = item.startCoordinate {
                header += " [GPS: \(formatCoord(start.lat, start.lon))"
                if let end = item.endCoordinate, end.lat != start.lat || end.lon != start.lon {
                    header += " → \(formatCoord(end.lat, end.lon))"
                }
                header += "]"
            }
            if let wpm = item.wordsPerMinute {
                header += " [~\(Int(wpm)) wpm, \(speakingPaceLabel(wpm))]"
            }
            return "\(header) \(item.text)"
        }.joined(separator: "\n\n")
    }

    private static func formatPlaceNames(_ places: [PlaceContext]) -> String? {
        guard !places.isEmpty else { return nil }
        let start = places.first { $0.role == .start }
        let end = places.first { $0.role == .end }
        if let start = start, let end = end {
            return "**Location:** Started near \(start.name) → ended near \(end.name)"
        } else if let start = start {
            return "**Location:** Near \(start.name)"
        }
        return nil
    }

    private static func speakingPaceLabel(_ wpm: Double) -> String {
        switch wpm {
        case ..<100: return "slow/thoughtful"
        case 100..<140: return "measured"
        case 140..<170: return "conversational"
        default: return "rapid/energized"
        }
    }

    private static func formatCoord(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.5f, %.5f", lat, lon)
    }

    private static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    private static func formatMeditations(_ meditations: [MeditationContext]) -> String? {
        guard !meditations.isEmpty else { return nil }
        let lines = meditations.map { m in
            let durationSec = Int(m.duration)
            let durationStr = durationSec < 60 ? "\(durationSec) sec" : "\(durationSec / 60) min \(durationSec % 60) sec"
            return "[\(timeFormatter.string(from: m.startDate)) – \(timeFormatter.string(from: m.endDate))] Meditated for \(durationStr)"
        }
        return lines.joined(separator: "\n")
    }

    private static func formatPaceContext(speeds: [Double]) -> String? {
        let moving = speeds.filter { $0 >= 0.3 }
        guard moving.count >= 10 else { return nil }
        let avgSpeed = moving.reduce(0, +) / Double(moving.count)
        guard let minSpeed = moving.min(), let maxSpeed = moving.max() else { return nil }
        let avgPace = formatPace(metersPerSecond: avgSpeed)
        let slowPace = formatPace(metersPerSecond: minSpeed)
        let fastPace = formatPace(metersPerSecond: maxSpeed)
        return "**Pace:** Average \(avgPace) (range: \(fastPace)–\(slowPace))"
    }

    private static func formatPace(metersPerSecond: Double) -> String {
        guard metersPerSecond > 0 else { return "—" }
        let usesMiles = Locale.current.measurementSystem == .us
        let metersPerUnit: Double = usesMiles ? 1609.34 : 1000.0
        let label = usesMiles ? "min/mi" : "min/km"
        let secondsPerUnit = metersPerUnit / metersPerSecond
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d %@", minutes, seconds, label)
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static func formatRecentWalks(_ snippets: [WalkSnippet]) -> String? {
        guard !snippets.isEmpty else { return nil }
        let lines = snippets.map { snippet in
            let dateStr = shortDateFormatter.string(from: snippet.date)
            if let place = snippet.placeName {
                return "[\(dateStr) – \(place)] \"\(snippet.transcriptionPreview)\""
            }
            return "[\(dateStr)] \"\(snippet.transcriptionPreview)\""
        }
        return "**Recent Walk Context (for continuity):**\n\n" + lines.joined(separator: "\n\n")
    }

    private static func formatMetadata(duration: Double, distance: Double, startDate: Date) -> String {
        let durationMin = Int(duration / 60)
        let distanceStr = distanceFormatter.string(from: Measurement(value: distance, unit: UnitLength.meters))
        let timeOfDay = timeOfDayDescription(startDate)

        let lunar = LunarPhase.current(date: startDate)
        return "Walk duration: \(durationMin) minutes | Distance: \(distanceStr) | Time: \(timeOfDay) on \(dateTimeFormatter.string(from: startDate)) | Moon: \(lunar.name) (\(Int(round(lunar.illumination * 100)))% illumination)"
    }

    private static func timeOfDayDescription(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "early morning"
        case 9..<12: return "morning"
        case 12..<14: return "midday"
        case 14..<17: return "afternoon"
        case 17..<20: return "evening"
        default: return "night"
        }
    }

    // MARK: - Prompt Builder

    private static func buildPrompt(preamble: String, instruction: String, transcription: String, meditations: String?, metadata: String, location: String?, pace: String?, recentWalks: String?, intention: String? = nil) -> String {
        var sections = """
            \(preamble)

            ---

            **Context:** \(metadata)
            """

        if let intention = intention {
            sections += "\n\n**Intention for this walk:** \"\(intention)\""
        }

        if let location = location {
            sections += "\n\n\(location)"
        }

        if let pace = pace {
            sections += "\n\n\(pace)"
        }

        sections += """


            **Walking Transcription:**

            \(transcription)
            """

        if let meditations = meditations {
            sections += """


            **Meditation Sessions:**

            \(meditations)
            """
        }

        if let recentWalks = recentWalks {
            sections += """


            \(recentWalks)
            """
        }

        var fullInstruction = instruction
        if let intention = intention {
            fullInstruction += " The walker set this intention before walking: '\(intention)'. Let this purpose guide your response."
        }

        sections += """


            ---

            \(fullInstruction)
            """

        return sections
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
