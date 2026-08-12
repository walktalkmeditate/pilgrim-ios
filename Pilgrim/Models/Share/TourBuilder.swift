import Foundation

enum TourRecordingKind: String { case spoken, ambient }

struct TourRecordingCandidate: Identifiable, Equatable {
    let id: Int
    let startTs: Int
    let endTs: Int
    let duration: Double
    let sizeBytes: Int
    let transcription: String?
    let wpm: Double?
    let autoKind: TourRecordingKind
    var includeInShare: Bool
    var kindOverride: TourRecordingKind?
    var fileURL: URL?
    let unavailableReason: String?

    var effectiveKind: TourRecordingKind { kindOverride ?? autoKind }
}

enum TourBuilder {

    static let maxRecordings = 12
    static let maxFileBytes = 15 * 1024 * 1024
    static let maxTotalBytes = 60 * 1024 * 1024
    static let maxTotalSeconds: Double = 2700

    /// A deliberate recording is presumed to be a voice: only a transcription
    /// that reads as non-speech (too few words, or implausibly slow) files
    /// the recording as ambience. The walker can override either way.
    static func classify(transcription: String?, wpm: Double?) -> TourRecordingKind {
        guard let text = transcription?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .spoken
        }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount < 8 { return .ambient }
        if let wpm, wpm < 30 { return .ambient }
        return .spoken
    }

    static func candidates(for walk: WalkInterface) -> [TourRecordingCandidate] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sorted = walk.voiceRecordings.sorted { $0.startDate < $1.startDate }
        return sorted.enumerated().compactMap { index, rec in
            guard !rec.fileRelativePath.isEmpty else { return nil }
            let url = docs.appendingPathComponent(rec.fileRelativePath)
            let startTs = Int(rec.startDate.timeIntervalSince1970)
            let endTs = Int(rec.endDate.timeIntervalSince1970)
            // The worker validates truncated integers and rejects the WHOLE
            // POST on end_ts <= start_ts — a sub-second blip recording must
            // be excluded here, not shipped.
            guard endTs > startTs else { return nil }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
            let unavailableReason: String?
            if size == nil || size == 0 {
                unavailableReason = "audio removed"
            } else if let size, size > maxFileBytes {
                unavailableReason = "too large to carry"
            } else {
                unavailableReason = nil
            }
            return TourRecordingCandidate(
                id: index,
                startTs: startTs,
                endTs: endTs,
                duration: rec.duration,
                sizeBytes: size ?? 0,
                transcription: rec.transcription,
                wpm: rec.wordsPerMinute,
                autoKind: classify(transcription: rec.transcription, wpm: rec.wordsPerMinute),
                includeInShare: unavailableReason == nil,
                kindOverride: nil,
                fileURL: unavailableReason == nil ? url : nil,
                unavailableReason: unavailableReason
            )
        }
    }

    static func totals(of candidates: [TourRecordingCandidate]) -> (count: Int, bytes: Int, seconds: Double) {
        let included = candidates.filter { $0.includeInShare && $0.unavailableReason == nil }
        return (included.count,
                included.reduce(0) { $0 + $1.sizeBytes },
                included.reduce(0) { $0 + $1.duration })
    }

    static func validationError(for candidates: [TourRecordingCandidate]) -> String? {
        let (count, bytes, seconds) = totals(of: candidates)
        if count > maxRecordings { return "A walk page carries at most \(maxRecordings) recordings — leave some out." }
        if bytes > maxTotalBytes { return "Recordings total \(bytes / 1_048_576) MB — the page carries at most 60 MB." }
        if seconds > maxTotalSeconds { return "Recordings total \(Int(seconds / 60)) minutes — the page carries at most 45." }
        return nil
    }

    static func tourItems(candidates: [TourRecordingCandidate], trimM: Int) -> (tour: SharePayload.Tour, files: [URL]) {
        let included = candidates.filter { $0.includeInShare && $0.unavailableReason == nil && $0.fileURL != nil }
        let recordings = included.enumerated().map { index, c in
            SharePayload.TourRecording(
                n: index + 1,
                startTs: c.startTs,
                endTs: c.endTs,
                duration: c.duration,
                kind: c.effectiveKind.rawValue,
                // Transcripts never leave the device: the page renders none, and
                // a 45-minute walk's transcripts would blow the 2MB POST budget.
                // Deliberate — do not wire c.transcription through.
                transcription: nil,
                wpm: c.wpm,
                sizeBytes: c.sizeBytes
            )
        }
        let files = included.compactMap(\.fileURL)
        return (SharePayload.Tour(recordings: recordings, trimM: trimM), files)
    }
}
