import XCTest
@testable import Pilgrim

final class TourBuilderTests: XCTestCase {

    func testClassify_noTranscriptionIsSpoken() {
        XCTAssertEqual(TourBuilder.classify(transcription: nil), .spoken)
    }

    func testClassify_fewWordsIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: "wind and birds"), .ambient)
    }

    func testClassify_slowContemplativeSpeechIsSpoken() {
        // 25 wpm over a 5-minute talk is a real pattern on real walks —
        // sparse words must not demote a deliberate talk to ambience.
        let words = Array(repeating: "word", count: 120).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words), .spoken)
    }

    func testClassify_realSpeechIsSpoken() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words), .spoken)
    }

    func testClassify_emptyTranscriptionIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: ""), .ambient)
    }

    func testClassify_whitespaceOnlyTranscriptionIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: "  \n "), .ambient)
    }

    private func candidate(id: Int, bytes: Int = 1_000_000, seconds: Double = 60, included: Bool = true, kind: TourRecordingKind = .spoken) -> TourRecordingCandidate {
        TourRecordingCandidate(id: id, startTs: 1000 + id * 100, endTs: 1050 + id * 100, duration: seconds, sizeBytes: bytes, transcription: nil, wpm: nil, autoKind: kind, includeInShare: included, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/\(id).m4a"), unavailableReason: nil, lat: nil, lon: nil)
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

    func testSoundscapeUrl_resolvesThroughManifest() {
        let manifest = AudioManifest(version: "1", assets: [
            AudioAsset(id: "stream-1", type: .soundscape, name: "stream", displayName: "Stream",
                       durationSec: 300, r2Key: "soundscape/stream.m4a", fileSizeBytes: 1_000_000, usageTags: [])
        ])
        // base/type/{id}.aac — the formula AudioDownloadManager fetches
        // with; r2Key would double the audio/ prefix (caught live: 404).
        XCTAssertEqual(
            TourBuilder.soundscapeUrl(selectedId: "stream-1", manifest: manifest),
            "https://cdn.pilgrimapp.org/audio/soundscape/stream-1.aac"
        )
        XCTAssertNil(TourBuilder.soundscapeUrl(selectedId: nil, manifest: manifest),
                     "silence chosen stays silence")
        XCTAssertNil(TourBuilder.soundscapeUrl(selectedId: "retired-id", manifest: manifest),
                     "a retired id must not become a dead link")
        XCTAssertNil(TourBuilder.soundscapeUrl(selectedId: "stream-1", manifest: nil))
    }

    func testTourItems_carriesSoundscapeUrl() {
        let (tour, _) = TourBuilder.tourItems(candidates: [candidate(id: 0)], trimM: 0,
                                              soundscapeUrl: "https://cdn.pilgrimapp.org/audio/soundscape/stream.m4a")
        XCTAssertEqual(tour.soundscapeUrl, "https://cdn.pilgrimapp.org/audio/soundscape/stream.m4a")
        let (bare, _) = TourBuilder.tourItems(candidates: [candidate(id: 0)], trimM: 0)
        XCTAssertNil(bare.soundscapeUrl)
    }

    func testTourItems_stripsTranscription() {
        let withTranscript = TourRecordingCandidate(id: 0, startTs: 1000, endTs: 1060, duration: 60, sizeBytes: 1_000_000, transcription: "some real speech", wpm: 120, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/0.m4a"), unavailableReason: nil, lat: nil, lon: nil)
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
        let long = (0..<7).map { candidate(id: $0, seconds: 1000) }        // 7000s > 6480
        XCTAssertNotNil(TourBuilder.validationError(for: long))
        let contemplative = (0..<6).map { candidate(id: $0, seconds: 1000) } // 6000s fits in 108 min
        XCTAssertNil(TourBuilder.validationError(for: contemplative))
    }

    func testValidation_excludedRecordingsDoNotCount() {
        let candidates = (0..<13).map { candidate(id: $0, included: $0 < 12) }
        XCTAssertNil(TourBuilder.validationError(for: candidates))
    }

    func testUnavailableCandidatesNeverEnterTour() {
        var removed = candidate(id: 1)
        removed = TourRecordingCandidate(id: 1, startTs: 1100, endTs: 1150, duration: 50, sizeBytes: 0, transcription: "kept transcript", wpm: nil, autoKind: .spoken, includeInShare: false, kindOverride: nil, fileURL: nil, unavailableReason: "audio removed", lat: nil, lon: nil)
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

    func testCandidatesCarryTheRecordingCoordinate() throws {
        let start = DateFactory.makeDate(2026, 5, 1, 8, 0, 0)
        let route = (0..<5).map { i in
            TempRouteDataSample(uuid: nil, timestamp: start.addingTimeInterval(Double(i) * 60), latitude: 42.0 + Double(i) * 0.001,
                                longitude: -8.0, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, speed: 1, direction: 0)
        }
        // A real file, not a fake path: an "audio removed" candidate is
        // excluded from tourItems entirely, so the coordinate has to survive
        // the same availability gate every other recording goes through.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let relativePath = "tourbuilder-coord-\(UUID().uuidString).m4a"
        let fileURL = docs.appendingPathComponent(relativePath)
        try TestAudioFile.writeSilentAudioFile(to: fileURL, duration: 0.2)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }

        let rec = TempVoiceRecording(uuid: nil, startDate: start.addingTimeInterval(125), endDate: start.addingTimeInterval(160),
                                     duration: 35, fileRelativePath: relativePath, transcription: nil)
        let walk = WalkDataFactory.makeWalk(startDate: start, routeData: route, voiceRecordings: [rec])
        let candidate = TourBuilder.candidates(for: walk).first
        XCTAssertEqual(candidate?.lat ?? 0, 42.002, accuracy: 0.0001)
        XCTAssertEqual(candidate?.lon ?? 0, -8.0, accuracy: 0.0001)
        let items = TourBuilder.tourItems(candidates: TourBuilder.candidates(for: walk), trimM: 0)
        XCTAssertEqual(items.tour.recordings.first?.lat ?? 0, 42.002, accuracy: 0.0001)
    }
}
