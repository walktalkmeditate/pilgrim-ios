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
        case .reflective: return "mirror.fill"
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
    let style: PromptStyle
    let text: String
}

struct PromptGenerator {

    struct RecordingContext {
        let text: String
        let timestamp: Date
        let startCoordinate: (lat: Double, lon: Double)?
        let endCoordinate: (lat: Double, lon: Double)?
    }

    static func generate(
        style: PromptStyle,
        recordings: [RecordingContext],
        duration: Double,
        distance: Double,
        startDate: Date
    ) -> GeneratedPrompt {
        let combinedText = formatRecordings(recordings)
        let metadata = formatMetadata(duration: duration, distance: distance, startDate: startDate)
        let prompt = buildPrompt(style: style, transcription: combinedText, metadata: metadata)
        return GeneratedPrompt(style: style, text: prompt)
    }

    static func generateAll(
        recordings: [RecordingContext],
        duration: Double,
        distance: Double,
        startDate: Date
    ) -> [GeneratedPrompt] {
        PromptStyle.allCases.map { style in
            generate(
                style: style,
                recordings: recordings,
                duration: duration,
                distance: distance,
                startDate: startDate
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
            return "\(header) \(item.text)"
        }.joined(separator: "\n\n")
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

    private static func formatMetadata(duration: Double, distance: Double, startDate: Date) -> String {
        let durationMin = Int(duration / 60)
        let distanceStr = distanceFormatter.string(from: Measurement(value: distance, unit: UnitLength.meters))
        let timeOfDay = timeOfDayDescription(startDate)

        return "Walk duration: \(durationMin) minutes | Distance: \(distanceStr) | Time: \(timeOfDay) on \(dateTimeFormatter.string(from: startDate))"
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

    private static func buildPrompt(style: PromptStyle, transcription: String, metadata: String) -> String {
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

        return """
            \(preamble)

            ---

            **Context:** \(metadata)

            **Walking Transcription:**

            \(transcription)

            ---

            \(instruction)
            """
    }
}
