import Foundation

enum PromptAssembler {

    /// `directives` and `detectedLanguageName` default to nil, meaning
    /// "compute here" — single-style callers stay unchanged, while
    /// `generateAll` computes both once and fans them out so a screen-open
    /// pays for one NLP pass instead of one per style.
    ///
    /// A voice that hoists the `Unchanged:` block and has no block to hoist
    /// produces NOTHING — the empty string, checked first, before any
    /// section is built. `ObliqueVoice`'s preamble and instruction both
    /// reference "the invariants named under Unchanged" unconditionally, so
    /// assembling it without the block hands the model an explicit
    /// invitation to invent one, which is this feature's worst failure mode.
    /// The picker's own gate (`PromptStyle.isAvailable(unchangedBlockPresent:)`)
    /// still stands and is still the thing the walker sees, but it is one
    /// view: any future share affordance, copy button, widget, or second
    /// prompt surface would bypass it. Making the assembler refuse puts the
    /// safety property where the prompt is actually built, so every present
    /// and future caller inherits it. Refusing here rather than filtering
    /// `.oblique` out of `PromptGenerator.generateAll` is deliberate — the
    /// filtered list would also delete the dimmed "Still listening" row the
    /// walker is meant to see, trading a safety fix for a UX regression.
    static func assemble(
        context: ActivityContext,
        voice: PromptVoice,
        directives: [String]? = nil,
        detectedLanguageName: String? = nil
    ) -> String {
        guard !voice.contextPolicy.hoistsUnchangedBlock || context.unchangedBlock != nil else { return "" }
        let metadata = ContextFormatter.formatMetadata(
            duration: context.duration,
            distance: context.distance,
            startDate: context.startDate,
            lunarPhase: context.lunarPhase,
            pauseDuration: context.pauses.reduce(0) { $0 + $1.duration }
        )

        var preamble = voice.preamble(hasSpeech: context.hasSpeech)
        if let characterNote = WalkCharacter.note(context: context) {
            preamble += " \(characterNote)"
        }

        var sections = "\(preamble)\n\n---\n\n**Context:** \(metadata)"
        if let weather = context.weather {
            sections += " | \(weather)"
        }
        if voice.contextPolicy.hoistsUnchangedBlock, let unchanged = context.unchangedBlock {
            sections += "\n\n\(unchanged)"
        }
        sections += contextDossier(context: context, policy: voice.contextPolicy)
        let dossier = selectedDossier(context: context, policy: voice.contextPolicy)
        sections += walkRecord(
            context: context,
            dossier: dossier,
            directives: directives,
            detectedLanguageName: detectedLanguageName
        )

        var fullInstruction = voice.instruction(hasSpeech: context.hasSpeech)
        if voice.contextPolicy.groundsInIntention, let intention = context.intention {
            fullInstruction += " Ground your response in the walker's stated intention: '\(intention)'. Return to it. Help them see how their walk — its pace, its pauses, its moments — spoke to this purpose."
        }

        sections += "\n\n---\n\n\(fullInstruction)"
        // Never the senses-only dossier: its content (weather, moon, place,
        // climb) carries no marker or thread claim to interpret, so a voice
        // reading only it (Creative, Gratitude) must not receive the
        // clinical-language guard or an interpretive key either — both are
        // about reading marker/thread numbers this voice was never shown.
        let threadsDossierForContract = voice.contextPolicy.includesThreadAnalysis ? dossier : nil
        sections += "\n\n\(responseContract(voice: voice, hasSpeech: context.hasSpeech, threadsDossier: threadsDossierForContract))"
        return sections
    }

    /// The dossier variant this voice's policy allows, drawn from the three
    /// already-rendered strings the builder carries on `ActivityContext` —
    /// never re-rendered here. A voice that suppresses thread analysis reads
    /// the senses-only variant (place, moon, weather, climb, photo adjacency,
    /// speech shape — never markerColoring) rather than losing the dossier's
    /// sensory content outright: the brief's original sketch branched on
    /// `includesMarkerLines` alone, which would have hidden markers from
    /// Creative and Gratitude while still leaking the "Threads across recent
    /// walks" / "Quiet this walk" sections their policy asks to suppress.
    private static func selectedDossier(context: ActivityContext, policy: PromptContextPolicy) -> String? {
        guard policy.includesThreadAnalysis else { return context.threadsDossierSensesOnly }
        return policy.includesMarkerLines ? context.threadsDossier : context.threadsDossierWithoutMarkers
    }

    /// The walk's circumstances: sky, practice, intention, place, and what
    /// the body did — everything the walker brought to or met on the path.
    ///
    /// The intention paragraph is scoped by `policy.groundsInIntention`
    /// alongside the instruction rider in `assemble` — the two are one
    /// instruction split across two places in the prompt, and scoping only
    /// one of them would leave the contradiction half-standing.
    private static func contextDossier(context: ActivityContext, policy: PromptContextPolicy) -> String {
        var sections = ""

        if let celestial = context.celestial {
            sections += "\n\n\(ContextFormatter.formatCelestial(celestial))"
        }

        sections += "\n\n\(practiceLexicon(context: context))"

        if policy.groundsInIntention, let intention = context.intention {
            sections += "\n\n**The walker's intention:** \"\(intention)\"\nThis intention was set deliberately before the walk began. It represents what the walker chose to carry with them. Let it be the lens through which you interpret everything below."
        }

        if let location = ContextFormatter.formatPlaceNames(context.placeNames) {
            sections += "\n\n\(location)"
        }

        if let pace = ContextFormatter.formatPaceContext(speeds: context.routeSpeeds) {
            sections += "\n\n\(pace)"
        }

        if let pauses = ContextFormatter.formatPauses(context.pauses) {
            sections += "\n\n\(pauses)"
        }

        if let elevation = ContextFormatter.formatElevation(ascent: context.ascent, descent: context.descent) {
            sections += "\n\n\(elevation)"
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

        return sections
    }

    /// Language code of the transcript's dominant language, or nil when no
    /// language clears the recognizer's confidence bar.
    static func detectedLanguageCode(context: ActivityContext) -> String? {
        guard context.hasSpeech else { return nil }
        return TranscriptNLP.detectLanguage(context.recordings.map(\.text).joined(separator: " "))
    }

    /// English display name of the transcript's dominant language.
    static func detectedLanguageName(context: ActivityContext) -> String? {
        languageName(forCode: detectedLanguageCode(context: context))
    }

    static func languageName(forCode code: String?) -> String? {
        code.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) }
    }

    /// What the walk produced — words, stillness, continuity with recent
    /// walks — closed by the directives that point at its patterns. `dossier`
    /// arrives pre-selected by `assemble` per the voice's context policy.
    private static func walkRecord(
        context: ActivityContext,
        dossier: String?,
        directives: [String]?,
        detectedLanguageName: String?
    ) -> String {
        var sections = ""

        let transcription = ContextFormatter.formatRecordings(context.recordings)
        if !transcription.isEmpty {
            sections += "\n\n**Walking Transcription:**\n\n\(transcription)"
        }

        if !transcription.isEmpty,
           let name = detectedLanguageName ?? Self.detectedLanguageName(context: context) {
            sections += "\n\n**Detected language:** \(name)"
        }

        if let meditations = ContextFormatter.formatMeditations(context.meditations) {
            sections += "\n\n**Meditation Sessions:**\n\n\(meditations)"
        }

        if let recentWalks = ContextFormatter.formatRecentWalks(context.recentWalkSnippets) {
            sections += "\n\n\(recentWalks)"
        }

        if let dossier {
            sections += "\n\n\(dossier)"
        }

        let resolvedDirectives = directives ?? AttentionDirectives.detect(context: context)
        if !resolvedDirectives.isEmpty {
            let bullets = resolvedDirectives.map { "- \($0)" }.joined(separator: "\n")
            sections += "\n\n**Attend to:**\n\(bullets)"
        }

        return sections
    }

    /// Teaches the downstream model the walk's ritual grammar in Pilgrim's
    /// own vocabulary, so route and pace data read as practice, not as
    /// fitness telemetry. Seek walks carry their story; a zero-arrival seek
    /// is named, not hidden.
    static func practiceLexicon(context: ActivityContext) -> String {
        switch context.mode {
        case .wander:
            return "**About this practice:** This walk was a wander — no destination, no goal; the path chose itself."
        case .seek:
            var text = "**About this practice:** This walk was a Seek. The walker surrendered the choice of destination: a seed cast hidden clearings across the map, veiled in fog, revealed only by nearness and stillness. Arriving is not achievement; it is consent to be led."
            if let story = context.seekStory {
                if story.arrivalTimes.isEmpty {
                    text += " No clearing was reached this time — the seek honors this too; some walks are about the looking."
                } else if let only = story.arrivalTimes.first, story.arrivalTimes.count == 1 {
                    text += " One clearing was found, reached in the \(ContextFormatter.timeOfDayDescription(only))."
                } else if let first = story.arrivalTimes.first, let last = story.arrivalTimes.last {
                    text += " \(story.arrivalTimes.count) clearings were found — the first in the \(ContextFormatter.timeOfDayDescription(first)), the last in the \(ContextFormatter.timeOfDayDescription(last))."
                }
            }
            return text
        }
    }

    /// The closing contract every prompt carries: what the response may not
    /// do (invent, flatten, switch language) plus the voice's own form
    /// constraints. This shapes the *reply's* quality — the part of the
    /// feature the walker actually experiences.
    static func responseContract(voice: PromptVoice, hasSpeech: Bool, threadsDossier: String?) -> String {
        var lines = voice.responseConstraints(hasSpeech: hasSpeech)
        if hasSpeech {
            lines.append("Respond in the language the walker speaks in the transcription.")
            lines.append("If more than one voice appears in the transcription, honor it as a conversation — attend to what happened between the speakers, and never guess at names.")
        }
        if let threadsDossier {
            lines.append("The thought-thread marker profiles are descriptive on-device linguistic signals, not assessments — interpret them gently, never produce clinical or diagnostic language, and never treat a single walk's numbers as meaningful on their own.")
            if let key = interpretiveKey(for: threadsDossier) {
                lines.append(key)
            }
        }
        lines.append("Draw only on what this walk actually holds — never invent details, events, or memories that are not in the context above.")
        let bullets = lines.map { "- \($0)" }.joined(separator: "\n")
        return "**How to respond:**\n\(bullets)"
    }

    /// How to read the marker signals — but only the ones this dossier
    /// actually printed. `ThreadsDossierFormatter.markerLine` prints "Markers
    /// unavailable" for a non-English recording and raw counts rather than
    /// shares below `densityFloorWords`, and the modal-lean clause sits
    /// behind three thresholds and is usually silent. Teaching a taxonomy the
    /// dossier withheld hands the model vocabulary with no referent, and it
    /// will find something to attach it to.
    ///
    /// The probes match the formatter's own phrasings. That coupling is the
    /// point — it is pinned by
    /// `testResponseContract_againstRealFormatterOutput_adaptsToWhatWasPrinted`,
    /// which runs the real formatter, so a phrasing change fails a test
    /// rather than silently suppressing the key on every walk.
    ///
    /// At most one line either way: the contract's accretion budget does not
    /// grow to pay for this.
    private static func interpretiveKey(for dossier: String) -> String? {
        var clauses: [String] = []
        if dossier.contains("absolutist words") {
            clauses.append("Read the absolutist-word share as how fixed the walker's framing was, and self-focus as how far they placed themselves at the centre of it.")
        } else if dossier.contains("raw counts only") {
            clauses.append("Read the absolutist and self-focus counts as a bare tally of how fixed the walker's framing was and how far they placed themselves at the centre of it — too few words to read as a rate, so do not weigh them.")
        }
        if dossier.contains("modal lean:") {
            clauses.append("Read the modal lean as the frame the walker was working inside — obligation means the frame constrained them, counterfactual means they were already replaying alternatives, possibility and tentative mean it was still open, intention means they had settled on a course, and desire means they were naming a want rather than a plan.")
        }
        guard !clauses.isEmpty else { return nil }
        return (clauses + ["None of these has a fixed meaning; read each through this walk's intention and practice."])
            .joined(separator: " ")
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
