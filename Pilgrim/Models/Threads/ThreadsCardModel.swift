import Foundation

struct ThreadsCardTheme: Equatable, Identifiable {
    let displayTerm: String
    let lemmas: [String]
    let statusNote: String?

    var id: String { displayTerm }
}

struct ThreadsCardModel: Equatable {
    let themes: [ThreadsCardTheme]
    let textureLine: String?
    let insightWords: [String]
    let hasInsight: Bool
}

enum ThreadsCardCopy {

    private static let ordinalWords: [Int: String] = [
        2: "second", 3: "third", 4: "fourth", 5: "fifth", 6: "sixth",
        7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth",
        11: "eleventh", 12: "twelfth"
    ]

    /// Ordinal words, never digits (spec principle 1). Beyond the table the
    /// copy stays soft instead of inventing "twenty-third"; a bare
    /// walksInWindow of 1 means the thread recurred outside the 30-day
    /// window — "returning", not a false ordinal.
    static func statusNote(for status: ThreadStatus?) -> String? {
        switch status {
        case .firstTime:
            return "first time"
        case .recurring(let walks):
            if walks <= 1 { return "returning" }
            guard let word = ordinalWords[walks] else { return "with you again" }
            return "\(word) walk now"
        case nil:
            return nil
        }
    }
}

enum ThreadsCardModelBuilder {

    static let maxThemes = 4

    /// Pure: threads in, card model out. Nil means no card — the summary
    /// must stay pixel-identical when nothing was found.
    static func model(
        walkUUID: UUID,
        threads: [WalkThread],
        recordings: [(uuid: UUID, transcript: String, wordsPerMinute: Double?)],
        contextsByRecording: [UUID: TranscriptContext],
        backfillComplete: Bool
    ) -> ThreadsCardModel? {
        // Two lemmas can share a display term (move/moving → "the move"):
        // one chip per term, and release later acts on the whole cohort. The
        // grouping runs over ALL threads first — a sibling lemma whose
        // appearances are all in earlier walks still joins its cohort, so
        // status history and release lemma sets stay cohort-complete — and
        // only cohorts present in this walk keep a chip. mentions/salience
        // below filter to walkUUID, so ranking is unaffected.
        let cohorts = Dictionary(grouping: threads, by: \.displayTerm)
            .filter { $0.value.contains { $0.appearances.contains { $0.walkUUID == walkUUID } } }
        guard !cohorts.isEmpty else { return nil }

        let totalWords = recordings
            .compactMap { contextsByRecording[$0.uuid]?.wordCount }
            .reduce(0, +)

        let ranked = cohorts
            .map { term, cohort -> (theme: ThreadsCardTheme, salience: Double, mentions: Int) in
                let merged = mergedThread(displayTerm: term, cohort: cohort)
                let mentions = merged.appearances
                    .filter { $0.walkUUID == walkUUID }
                    .reduce(0) { $0 + $1.mentionCount }
                let salience = totalWords > 0 ? Double(mentions) / Double(totalWords) : 0
                let status = ThreadStore.status(
                    of: merged, atWalk: walkUUID, backfillComplete: backfillComplete
                )
                return (
                    ThreadsCardTheme(
                        displayTerm: term,
                        lemmas: cohort.map(\.lemma).sorted(),
                        statusNote: ThreadsCardCopy.statusNote(for: status)
                    ),
                    salience,
                    mentions
                )
            }
            .sorted {
                ($0.salience, $0.mentions, $1.theme.displayTerm)
                    > ($1.salience, $1.mentions, $0.theme.displayTerm)
            }
            .prefix(maxThemes)
            .map(\.theme)

        let englishTranscripts = recordings
            .filter { contextsByRecording[$0.uuid]?.languageCode == "en" }
            .map(\.transcript)
        let insightWords = ThreadsTexture.insightWords(in: englishTranscripts)
        let hasInsight = insightWords.count >= ThreadsTexture.insightFloor

        let wpms = recordings.compactMap(\.wordsPerMinute)
        let meanWPM = wpms.isEmpty ? nil : wpms.reduce(0, +) / Double(wpms.count)

        return ThreadsCardModel(
            themes: Array(ranked),
            textureLine: ThreadsTexture.line(
                meanWordsPerMinute: meanWPM,
                hasInsight: hasInsight
            ),
            insightWords: insightWords,
            hasInsight: hasInsight
        )
    }

    /// One pseudo-thread per cohort so ThreadStore.status sees the cohort's
    /// full history — a first-time claim is only true if NO lemma in the
    /// cohort appeared earlier.
    static func mergedThread(displayTerm: String, cohort: [WalkThread]) -> WalkThread {
        WalkThread(
            lemma: cohort.map(\.lemma).sorted().first ?? displayTerm,
            displayTerm: displayTerm,
            appearances: cohort.flatMap(\.appearances)
                .sorted { ($0.date, $0.recordingUUID.uuidString) < ($1.date, $1.recordingUUID.uuidString) }
        )
    }
}
