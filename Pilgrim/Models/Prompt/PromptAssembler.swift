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

        if !context.photoContexts.isEmpty {
            sections += formatPhotoSection(context.photoContexts, arc: context.narrativeArc)
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

    private static func formatPhotoSection(
        _ photos: [PhotoContextEntry],
        arc: NarrativeArc?
    ) -> String {
        var section = "\n\n**Photos pinned along the walk:**"
        for entry in photos {
            var line = "\nPhoto \(entry.index) (\(entry.distanceIntoWalk), \(entry.time), GPS: \(ContextFormatter.formatCoord(entry.coordinate.lat, entry.coordinate.lon))):"
            if !entry.context.tags.isEmpty {
                line += "\n  Scene: \(entry.context.tags.joined(separator: ", "))"
            }
            if !entry.context.detectedText.isEmpty {
                line += "\n  Text found: \(entry.context.detectedText.map { "\"\($0)\"" }.joined(separator: ", "))"
            }
            line += "\n  People: \(entry.context.people == 0 ? "none" : "\(entry.context.people)")"
            if !entry.context.animals.isEmpty {
                line += "\n  Animals: \(entry.context.animals.joined(separator: ", "))"
            }
            line += "\n  Outdoor: \(entry.context.outdoor ? "yes" : "no")"
            line += "\n  Focal area: \(entry.context.salientRegion)"
            section += line
        }
        if let arc {
            let arcDesc: String
            switch arc.attentionArc {
            case "detail_to_wide": arcDesc = "Attention progressed from close-up detail to wider views"
            case "wide_to_detail": arcDesc = "Attention narrowed from wide views to close-up detail"
            case "consistently_close": arcDesc = "Consistently focused on close-up detail throughout"
            case "consistently_wide": arcDesc = "Consistently captured wide, open views throughout"
            case "single": arcDesc = "A single captured moment"
            default: arcDesc = "A varied visual rhythm throughout"
            }
            let solitudeDesc = arc.solitude == "alone"
                ? "A solitary walk — no people in any photo."
                : arc.solitude == "with_others"
                    ? "People present in the photos — a social walk."
                    : "Some moments alone, some with others."
            section += "\n\nVisual narrative: \(arcDesc). \(solitudeDesc)"
            if !arc.recurringTheme.isEmpty {
                section += " Recurring theme: \(arc.recurringTheme.joined(separator: ", "))."
            }
            section += "\nColor progression: \(arc.dominantColors.joined(separator: " → "))"
        }
        return section
    }
}
