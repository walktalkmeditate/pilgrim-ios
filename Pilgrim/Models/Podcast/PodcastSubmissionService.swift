import Foundation
import AVFoundation

final class PodcastSubmissionService {

    static let shared = PodcastSubmissionService()

    private let workerBase = "https://walk.pilgrimapp.org"
    private let maxChunkDuration: TimeInterval = 15 * 60
    private let minTotalDuration: TimeInterval = 12 * 60
    private let maxTotalDuration: TimeInterval = 60 * 60

    private init() {}

    // MARK: - Eligibility

    func isEligible(walk: WalkInterface) -> Bool {
        let recordings = walk.voiceRecordings
        guard !recordings.isEmpty else { return false }

        let totalDuration = recordings.reduce(0.0) { $0 + $1.duration }
        guard totalDuration >= minTotalDuration else { return false }
        guard totalDuration <= maxTotalDuration else { return false }

        if hasSubmittedToday() { return false }

        return true
    }

    private func hasSubmittedToday() -> Bool {
        guard let lastDate = UserPreferences.lastPodcastSubmissionDate.value else { return false }
        return lastDate == Self.todayString()
    }

    var hasConsent: Bool {
        UserPreferences.podcastConsentGiven.value
    }

    func grantConsent() {
        UserPreferences.podcastConsentGiven.value = true
    }

    // MARK: - Submit

    func submit(walk: WalkInterface, deviceToken: String) async throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let submissionId = generateSubmissionId()

        var uploadedRecordings: [RecordingInfo] = []

        for (index, recording) in walk.voiceRecordings.enumerated() {
            let audioURL = docs.appendingPathComponent(recording.fileRelativePath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }

            if recording.duration > maxChunkDuration {
                let chunks = try await splitAudio(url: audioURL, maxDuration: maxChunkDuration)
                for (chunkIndex, chunkURL) in chunks.enumerated() {
                    let name = "recording_\(index + 1)_part\(chunkIndex + 1).m4a"
                    let key = try await uploadFile(
                        url: chunkURL,
                        submissionId: submissionId,
                        fileName: name,
                        fileIndex: index,
                        deviceToken: deviceToken
                    )
                    let chunkDuration = try await audioDuration(url: chunkURL)
                    uploadedRecordings.append(RecordingInfo(
                        fileName: name,
                        r2Key: key,
                        duration: chunkDuration,
                        transcription: chunkIndex == 0 ? recording.transcription : nil
                    ))
                    try? FileManager.default.removeItem(at: chunkURL)
                }
            } else {
                let name = "recording_\(index + 1).m4a"
                let key = try await uploadFile(
                    url: audioURL,
                    submissionId: submissionId,
                    fileName: name,
                    fileIndex: index,
                    deviceToken: deviceToken
                )
                uploadedRecordings.append(RecordingInfo(
                    fileName: name,
                    r2Key: key,
                    duration: recording.duration,
                    transcription: recording.transcription
                ))
            }
        }

        try await submitMetadata(
            walk: walk,
            submissionId: submissionId,
            recordings: uploadedRecordings,
            deviceToken: deviceToken
        )

        await MainActor.run {
            UserPreferences.lastPodcastSubmissionDate.value = Self.todayString()
        }
    }

    // MARK: - Upload

    private func uploadFile(
        url: URL,
        submissionId: String,
        fileName: String,
        fileIndex: Int,
        deviceToken: String
    ) async throws -> String {
        let data = try Data(contentsOf: url)

        var request = URLRequest(url: URL(string: "\(workerBase)/api/podcast/upload")!)
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        request.setValue(submissionId, forHTTPHeaderField: "X-Submission-Id")
        request.setValue(String(fileIndex), forHTTPHeaderField: "X-File-Index")
        request.setValue(fileName, forHTTPHeaderField: "X-File-Name")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw SubmissionError.uploadFailed(fileName)
        }

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let key = json?["key"] as? String else {
            throw SubmissionError.uploadFailed(fileName)
        }

        return key
    }

    // MARK: - Submit Metadata

    private func submitMetadata(
        walk: WalkInterface,
        submissionId: String,
        recordings: [RecordingInfo],
        deviceToken: String
    ) async throws {
        let first = walk.routeData.first
        var weather: String?
        if let condition = walk.weatherCondition {
            weather = condition
            if let temp = walk.weatherTemperature {
                weather = "\(condition), \(Int(temp))\u{00B0}C"
            }
        }

        let payload: [String: Any] = [
            "submission_id": submissionId,
            "metadata": [
                "weather": weather as Any,
                "intention": walk.comment as Any,
                "distance_km": walk.distance / 1000,
                "active_duration": walk.activeDuration,
                "talk_duration": walk.talkDuration,
                "meditate_duration": walk.meditateDuration,
                "date": Self.todayString(),
                "start_lat": first?.latitude as Any,
                "start_lon": first?.longitude as Any,
            ],
            "recordings": recordings.map { rec in
                var dict: [String: Any] = [
                    "file_name": rec.fileName,
                    "r2_key": rec.r2Key,
                    "duration": rec.duration,
                ]
                if let t = rec.transcription { dict["transcription"] = t }
                return dict
            },
        ]

        var request = URLRequest(url: URL(string: "\(workerBase)/api/podcast/submit")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceToken, forHTTPHeaderField: "X-Device-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw SubmissionError.submissionFailed
        }
    }

    // MARK: - Audio Splitting

    private func splitAudio(url: URL, maxDuration: TimeInterval) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let totalDuration = try await asset.load(.duration).seconds
        let chunkCount = Int(ceil(totalDuration / maxDuration))
        var chunks: [URL] = []

        for i in 0..<chunkCount {
            let start = CMTime(seconds: Double(i) * maxDuration, preferredTimescale: 600)
            let end = CMTime(seconds: min(Double(i + 1) * maxDuration, totalDuration), preferredTimescale: 600)
            let range = CMTimeRange(start: start, end: end)

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("podcast_chunk_\(i)_\(UUID().uuidString.prefix(8)).m4a")

            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw SubmissionError.splitFailed
            }

            session.outputURL = tempURL
            session.outputFileType = .m4a
            session.timeRange = range

            await session.export()

            guard session.status == .completed else {
                throw SubmissionError.splitFailed
            }

            chunks.append(tempURL)
        }

        return chunks
    }

    private func audioDuration(url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        return try await asset.load(.duration).seconds
    }

    // MARK: - Helpers

    private struct RecordingInfo {
        let fileName: String
        let r2Key: String
        let duration: Double
        let transcription: String?
    }

    private func generateSubmissionId() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<12).map { _ in chars.randomElement()! })
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    enum SubmissionError: LocalizedError {
        case uploadFailed(String)
        case submissionFailed
        case splitFailed

        var errorDescription: String? {
            switch self {
            case .uploadFailed(let name): return "Failed to upload \(name)."
            case .submissionFailed: return "Failed to submit walk."
            case .splitFailed: return "Failed to split audio recording."
            }
        }
    }
}
