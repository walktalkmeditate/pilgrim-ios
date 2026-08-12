import XCTest
@testable import Pilgrim

final class TourBuilderTests: XCTestCase {

    func testClassify_noTranscriptionIsSpoken() {
        XCTAssertEqual(TourBuilder.classify(transcription: nil, wpm: nil), .spoken)
    }

    func testClassify_fewWordsIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: "wind and birds", wpm: 200), .ambient)
    }

    func testClassify_slowSpeechIsAmbient() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words, wpm: 12), .ambient)
    }

    func testClassify_realSpeechIsSpoken() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words, wpm: 110), .spoken)
    }

    func testClassify_transcriptionWithoutWpmUsesWordCountOnly() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words, wpm: nil), .spoken)
    }

    func testClassify_emptyTranscriptionIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: "", wpm: nil), .ambient)
    }

    func testClassify_whitespaceOnlyTranscriptionIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: "  \n ", wpm: 200), .ambient)
    }

    private func candidate(id: Int, bytes: Int = 1_000_000, seconds: Double = 60, included: Bool = true, kind: TourRecordingKind = .spoken) -> TourRecordingCandidate {
        TourRecordingCandidate(id: id, startTs: 1000 + id * 100, endTs: 1050 + id * 100, duration: seconds, sizeBytes: bytes, transcription: nil, wpm: nil, autoKind: kind, includeInShare: included, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/\(id).m4a"), unavailableReason: nil)
    }

    func testTourItems_renumbersAfterExclusion() {
        let candidates = [candidate(id: 0), candidate(id: 1, included: false), candidate(id: 2)]
        let (tour, files) = TourBuilder.tourItems(candidates: candidates, trimM: 150)
        XCTAssertEqual(tour.recordings.map(\.n), [1, 2])
        XCTAssertEqual(tour.recordings[1].startTs, 1200)
        XCTAssertEqual(tour.trimM, 150)
        XCTAssertEqual(files.map(\.lastPathComponent), ["0.m4a", "2.m4a"])
    }

    func testTourItems_kindOverrideWins() {
        var flipped = candidate(id: 0, kind: .spoken)
        flipped.kindOverride = .ambient
        let (tour, _) = TourBuilder.tourItems(candidates: [flipped], trimM: 0)
        XCTAssertEqual(tour.recordings[0].kind, "ambient")
    }

    func testTourItems_payloadAndFilesAlwaysAlign() {
        var urlless = candidate(id: 1)
        urlless.fileURL = nil
        let (tour, files) = TourBuilder.tourItems(candidates: [candidate(id: 0), urlless, candidate(id: 2)], trimM: 0)
        XCTAssertEqual(tour.recordings.count, files.count)
        XCTAssertEqual(files.map(\.lastPathComponent), ["0.m4a", "2.m4a"])
    }

    func testTourItems_stripsTranscription() {
        let withTranscript = TourRecordingCandidate(id: 0, startTs: 1000, endTs: 1060, duration: 60, sizeBytes: 1_000_000, transcription: "some real speech", wpm: 120, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/0.m4a"), unavailableReason: nil)
        let (tour, _) = TourBuilder.tourItems(candidates: [withTranscript], trimM: 0)
        XCTAssertNil(tour.recordings[0].transcription, "transcripts never leave the device — the page renders none of them")
    }

    func testValidation_overTwelveRecordingsFails() {
        let candidates = (0..<13).map { candidate(id: $0) }
        XCTAssertNotNil(TourBuilder.validationError(for: candidates))
        XCTAssertNil(TourBuilder.validationError(for: Array(candidates.prefix(12))))
    }

    func testValidation_totalBytesAndSecondsCaps() {
        let heavy = (0..<5).map { candidate(id: $0, bytes: 14_000_000) }   // 70MB
        XCTAssertNotNil(TourBuilder.validationError(for: heavy))
        let long = (0..<3).map { candidate(id: $0, seconds: 1000) }        // 3000s
        XCTAssertNotNil(TourBuilder.validationError(for: long))
    }

    func testValidation_excludedRecordingsDoNotCount() {
        let candidates = (0..<13).map { candidate(id: $0, included: $0 < 12) }
        XCTAssertNil(TourBuilder.validationError(for: candidates))
    }

    func testUnavailableCandidatesNeverEnterTour() {
        var removed = candidate(id: 1)
        removed = TourRecordingCandidate(id: 1, startTs: 1100, endTs: 1150, duration: 50, sizeBytes: 0, transcription: "kept transcript", wpm: nil, autoKind: .spoken, includeInShare: false, kindOverride: nil, fileURL: nil, unavailableReason: "audio removed")
        let (tour, files) = TourBuilder.tourItems(candidates: [candidate(id: 0), removed], trimM: 0)
        XCTAssertEqual(tour.recordings.count, 1)
        XCTAssertEqual(files.count, 1)
    }

    // MARK: - candidates(for:)

    func testCandidates_availableFileIncluded() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Flat filename, deliberately outside Documents/recordings — the app
        // host's OrphanRecordingSweep owns that directory and would race this file.
        let relativePath = "tourbuilder-available-\(UUID().uuidString).m4a"
        let fileURL = docs.appendingPathComponent(relativePath)
        try TestAudioFile.writeSilentAudioFile(to: fileURL, duration: 0.2)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let recording = WalkDataFactory.makeVoiceRecording(fileRelativePath: relativePath)
        let walk = WalkDataFactory.makeWalk(voiceRecordings: [recording])

        let candidates = TourBuilder.candidates(for: walk)

        let found = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertNil(found.unavailableReason)
        XCTAssertTrue(found.includeInShare)
        let expectedSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int)
        XCTAssertEqual(found.sizeBytes, expectedSize)
        XCTAssertEqual(found.fileURL, fileURL)
    }

    func testCandidates_missingFileMarkedAudioRemoved() {
        let recording = WalkDataFactory.makeVoiceRecording(fileRelativePath: "tourbuilder-missing-\(UUID().uuidString).m4a")
        let walk = WalkDataFactory.makeWalk(voiceRecordings: [recording])

        let candidates = TourBuilder.candidates(for: walk)

        XCTAssertEqual(candidates.count, 1, "a recording with no file on disk is still a candidate — just an unavailable one")
        XCTAssertEqual(candidates.first?.unavailableReason, "audio removed")
        XCTAssertEqual(candidates.first?.includeInShare, false)
        XCTAssertNil(candidates.first?.fileURL)
    }

    func testCandidates_subSecondBlipExcluded() {
        let start = DateFactory.makeDate(2024, 6, 15, 9, 5, 0)
        let recording = WalkDataFactory.makeVoiceRecording(startDate: start, endDate: start.addingTimeInterval(0.4))
        let walk = WalkDataFactory.makeWalk(voiceRecordings: [recording])

        let candidates = TourBuilder.candidates(for: walk)

        XCTAssertTrue(candidates.isEmpty, "a recording whose start/end truncate to the same Int second must not appear as a candidate at all — not even an unavailable one")
    }

    func testCandidates_sortedByStartDate() {
        let early = WalkDataFactory.makeVoiceRecording(
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 9, 0, 30)
        )
        let late = WalkDataFactory.makeVoiceRecording(
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 10, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 9, 10, 30)
        )
        // Walk stores them out of chronological order.
        let walk = WalkDataFactory.makeWalk(voiceRecordings: [late, early])

        let candidates = TourBuilder.candidates(for: walk)

        XCTAssertEqual(candidates.map(\.startTs), candidates.map(\.startTs).sorted(), "candidates must come back sorted by start date regardless of storage order")
        XCTAssertEqual(candidates.first?.startTs, Int(early.startDate.timeIntervalSince1970))
        XCTAssertEqual(candidates.last?.startTs, Int(late.startDate.timeIntervalSince1970))
    }
}
