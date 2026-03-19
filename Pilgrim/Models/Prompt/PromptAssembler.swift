import Foundation

enum PromptAssembler {

    static func assemble(context: ActivityContext, voice: PromptVoice) -> String {
        let transcription = ContextFormatter.formatRecordings(context.recordings)
        let meditations = ContextFormatter.formatMeditations(context.meditations)
        let metadata = ContextFormatter.formatMetadata(
            duration: context.duration,
            distance: context.distance,
            startDate: context.startDate,
            lunarPhase: context.lunarPhase
        )
        let location = ContextFormatter.formatPlaceNames(context.placeNames)
        let pace = ContextFormatter.formatPaceContext(speeds: context.routeSpeeds)
        let recentWalks = ContextFormatter.formatRecentWalks(context.recentWalkSnippets)

        let preamble = voice.preamble(hasSpeech: context.hasSpeech)
        let instruction = voice.instruction(hasSpeech: context.hasSpeech)

        var sections = """
            \(preamble)

            ---

            **Context:** \(metadata)
            """

        if let weather = context.weather {
            sections += " | \(weather)"
        }

        if let celestial = context.celestial {
            let celestialText = ContextFormatter.formatCelestial(celestial)
            sections += "\n\n\(celestialText)"
        }

        if let intention = context.intention {
            sections += "\n\n**The walker's intention:** \"\(intention)\"\nThis intention was set deliberately before the walk began. It represents what the walker chose to carry with them. Let it be the lens through which you interpret everything below."
        }

        if let location = location {
            sections += "\n\n\(location)"
        }

        if let pace = pace {
            sections += "\n\n\(pace)"
        }

        if !context.waypoints.isEmpty {
            let lines = context.waypoints.map { wp in
                "[\(ContextFormatter.timeFormatter.string(from: wp.timestamp)), GPS: \(ContextFormatter.formatCoord(wp.coordinate.lat, wp.coordinate.lon))] \(wp.label)"
            }.joined(separator: "\n")
            sections += "\n\n**Waypoints marked during walk:**\n\(lines)"
        }

        if !transcription.isEmpty {
            sections += """


            **Walking Transcription:**

            \(transcription)
            """
        }

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
        if let intention = context.intention {
            fullInstruction += " Ground your response in the walker's stated intention: '\(intention)'. Return to it. Help them see how their walk — its pace, its pauses, its moments — spoke to this purpose."
        }

        sections += """


            ---

            \(fullInstruction)
            """

        return sections
    }
}
