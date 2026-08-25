import XCTest
@testable import Pilgrim

/// Theme-marker coloring and photo adjacency tests, split from
/// `DossierSensesTests` to keep both files under the file_length /
/// type_body_length lint gates (plan house rule: split rather than accept a
/// new warning). Shares that class's fixtures (`makeInput`, `thread`,
/// `appearance`, `currentRecording`, `fix`, `Self.walkStart`) via extension.
extension DossierSensesTests {

    // MARK: - Tokenizer parity

    func testWordTokenOffsets_matchesWordTokensExactly() {
        let text = "Don't stop — the move MUST happen, always... whole-hearted?"
        XCTAssertEqual(TranscriptNLP.wordTokenOffsets(in: text).map(\.token),
                       TranscriptNLP.wordTokens(in: text),
                       "two tokenizers means diverging denominators — offsets must ride the same split")
    }

    func testWordTokenOffsets_matchesWordTokensExactly_combiningDiacritic() {
        // "café" written as base "e" + a combining acute accent (U+0301) —
        // one Swift `Character`, two Unicode scalars. A per-Character
        // all-scalars-are-letters check would treat the whole grapheme as
        // non-letter and drop it; a single shared tokenizer cannot.
        let text = "walking near the cafe\u{0301} today"
        XCTAssertEqual(TranscriptNLP.wordTokenOffsets(in: text).map(\.token),
                       TranscriptNLP.wordTokens(in: text),
                       "a combining-mark word must tokenize identically in both — one tokenizer, no exceptions")
    }

    // MARK: - Theme-marker coloring

    /// "move" at offsets with absolutist words packed around it; two more
    /// absolutist words sit far outside the mention windows (the last two
    /// repeats of the filler) so the "rest of the walk" has a nonzero
    /// denominator — the ordinary vs-rest branch.
    private var coloredTranscript: String {
        let prefix = "the move must always happen and everything about the move is completely certain now "
        let neutralFiller = "walking along the river path watching herons drift over quiet water today "
        let distantAbsolutist = "walking along the river path watching herons drift over quiet water always "
        return prefix + String(repeating: neutralFiller, count: 4) + String(repeating: distantAbsolutist, count: 2)
    }

    /// Same clustering, but every absolutist word in the transcript sits
    /// inside the mention windows — the rest of the walk holds none, so the
    /// ratio falls back to vs-overall density (spec: an under-claim, never
    /// an overstatement).
    private var coloredTranscriptNoRestAbsolutist: String {
        "the move must always happen and everything about the move is completely certain now " +
        String(repeating: "walking along the river path watching herons drift over quiet water today ", count: 6)
    }

    private func mentionOffsets(of word: String, in text: String) -> [ThemeMention] {
        var mentions: [ThemeMention] = []
        var search = text.startIndex
        while let range = text.range(of: word, range: search..<text.endIndex) {
            mentions.append(ThemeMention(start: text.distance(from: text.startIndex, to: range.lowerBound),
                                         length: word.count))
            search = range.upperBound
        }
        return mentions
    }

    func testMarkerColoring_clusteredAbsolutistWords_fire() {
        let text = coloredTranscript
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 2, salience: 0.05,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertEqual(
            DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
            "Absolutist words cluster around 'the move' — four times the density of the rest of the walk's speech."
        )
    }

    func testMarkerColoring_restHoldsNoAbsolutistWords_fallsBackToVsOverallRatio() {
        let text = coloredTranscriptNoRestAbsolutist
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 2, salience: 0.05,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertEqual(
            DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
            "Absolutist words cluster around 'the move' — three times the density of the rest of the walk's speech.",
            "the rest of the walk holds zero absolutist words — the ratio falls back to vs-overall density"
        )
    }

    func testMarkerColoring_fewerThanThreeAbsolutistTokensInWindows_doesNotFire() {
        let text = "the move must happen soon " +
            String(repeating: "walking along the river path watching herons drift over quiet water ", count: 6)
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 1, salience: 0.02,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertNil(DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
                     "≥3 absolutist tokens in windows is a binding floor")
    }

    func testMarkerColoring_uniformAbsolutistSpread_doesNotFire() {
        let text = String(repeating: "every path always leads somewhere and the move waits completely still ", count: 8)
        let theme = Theme(lemma: "move", displayTerm: "the move", mentionCount: 8, salience: 0.1,
                          mentions: mentionOffsets(of: "move", in: text))
        XCTAssertNil(DossierSenses.markerLine(theme: theme, displayTerm: "the move", text: text),
                     "uniform density can never reach 2× overall — no clustering, no claim")
    }

    func testMarkerColoring_viaSense_usesActiveThreadOrderAndSuppression() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let text = coloredTranscript
        let recording = DossierSenses.CurrentRecording(
            uuid: recUUID, start: Self.walkStart, end: Self.walkStart.addingTimeInterval(120),
            text: text, wordCount: TranscriptNLP.wordCount(in: text),
            themes: [Theme(lemma: "move", displayTerm: "the move", mentionCount: 2, salience: 0.05,
                           mentions: mentionOffsets(of: "move", in: text))]
        )
        let input = makeInput(
            currentWalkUUID: walkUUID,
            currentRecordings: [recording],
            threads: [thread(lemma: "move", display: "the move",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])]
        )
        XCTAssertEqual(DossierSenses.markerColoring(input: input, suppressed: [])?.lemma, "move")
        XCTAssertNil(DossierSenses.markerColoring(input: input, suppressed: ["move"]))
    }

    // MARK: - Photo adjacency

    func testPhotoAdjacency_nearAndSoon_fires() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(400),
                           coordinate: .init(latitude: 42.87825, longitude: -8.5448))],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertEqual(
            DossierSenses.photoAdjacency(input: input, suppressed: []),
            DossierSenses.SenseLine(text: "A photo was taken near where 'music' was spoken.", lemma: "music")
        )
    }

    func testPhotoAdjacency_nearButLate_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(800),
                           coordinate: .init(latitude: 42.87825, longitude: -8.5448))],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []),
                     "680 s after the recording ended exceeds the 10-minute tie")
    }

    func testPhotoAdjacency_soonButFar_doesNotFire() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(60),
                           coordinate: .init(latitude: 42.8792, longitude: -8.5448))],  // ~111 m north
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []))
    }

    func testPhotoAdjacency_recordingFailingHygiene_doesNotParticipate() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(60),
                           coordinate: .init(latitude: 42.8782, longitude: -8.5448))],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448, accuracy: 150)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []))
    }

    func testPhotoAdjacency_photoWithoutCoordinate_doesNotParticipate() {
        let walkUUID = UUID()
        let recUUID = UUID()
        let input = makeInput(
            currentWalkUUID: walkUUID,
            photos: [.init(capturedAt: Self.walkStart.addingTimeInterval(60), coordinate: nil)],
            currentRecordings: [currentRecording(uuid: recUUID, start: Self.walkStart,
                                                 end: Self.walkStart.addingTimeInterval(120),
                                                 themeLemmas: ["music"])],
            threads: [thread(lemma: "music",
                             appearances: [appearance(recording: recUUID, walk: walkUUID, date: Self.walkStart)])],
            fixes: [recUUID: fix(lat: 42.8782, lon: -8.5448)]
        )
        XCTAssertNil(DossierSenses.photoAdjacency(input: input, suppressed: []))
    }
}
