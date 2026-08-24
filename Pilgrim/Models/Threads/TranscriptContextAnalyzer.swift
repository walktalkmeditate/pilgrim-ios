import Foundation

enum TranscriptContextAnalyzer {

    /// Themes are extracted from the full transcript so mention offsets stay
    /// valid for excerpt display, then any theme whose every mention falls
    /// inside an ASR-flagged fragment is dropped — a hallucinated fragment
    /// can echo a real theme but never found one (spec: Error handling).
    static func analyze(
        recordingUUID: UUID,
        transcript: String,
        flaggedFragments: [String] = []
    ) -> TranscriptContext {
        let language = TranscriptNLP.detectLanguage(transcript)
        let flaggedRanges = characterRanges(of: flaggedFragments, in: transcript)

        let themes = ThemeExtractor.themes(in: transcript, languageCode: language)
            .filter { theme in
                flaggedRanges.isEmpty || theme.mentions.contains { mention in
                    !flaggedRanges.contains { $0.contains(mention.start) }
                }
            }

        let analysisText = flaggedFragments.reduce(transcript) {
            $0.replacingOccurrences(of: $1, with: " ")
        }

        return TranscriptContext(
            schemaVersion: TranscriptContext.currentSchemaVersion,
            recordingUUID: recordingUUID,
            transcriptHash: TranscriptContextStore.hash(of: transcript),
            languageCode: language,
            wordCount: TranscriptNLP.wordCount(in: transcript),
            themes: themes,
            markers: MarkerAnalyzer.compute(text: analysisText, languageCode: language)
        )
    }

    /// `saved` is false only when the store failed to persist the context
    /// (encode/write error) — the backfill uses it to decide whether an item
    /// is accounted for. A tombstone-blocked save reports true.
    @discardableResult
    static func analyzeAndStore(
        recordingUUID: UUID,
        transcript: String,
        flaggedFragments: [String] = [],
        store: TranscriptContextStore = .shared
    ) -> (context: TranscriptContext, saved: Bool) {
        let context = analyze(
            recordingUUID: recordingUUID,
            transcript: transcript,
            flaggedFragments: flaggedFragments
        )
        let saved = store.save(context)
        return (context, saved)
    }

    /// Every occurrence, not just the first — repeated hallucination is the
    /// canonical Whisper failure shape.
    private static func characterRanges(of fragments: [String], in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for fragment in fragments where !fragment.isEmpty {
            var searchStart = text.startIndex
            while let range = text.range(of: fragment, range: searchStart..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                ranges.append(start..<(start + text.distance(from: range.lowerBound, to: range.upperBound)))
                searchStart = range.upperBound
            }
        }
        return ranges
    }
}
