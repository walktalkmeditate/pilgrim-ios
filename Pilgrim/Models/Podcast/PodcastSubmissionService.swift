import Foundation
import CoreStore

final class PodcastSubmissionService {

    static let shared = PodcastSubmissionService()

    private let workerBase = "https://walk.pilgrimapp.org"
    private let minTotalDuration: TimeInterval = 12 * 60
    private let maxTotalDuration: TimeInterval = 108 * 60

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

    func submit(walk: WalkInterface, deviceToken: String, shareURL: String? = nil, reflection: String? = nil) async throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let submissionId = generateSubmissionId()

        var uploadedRecordings: [RecordingInfo] = []

        let freshRecordings: [VoiceRecordingInterface] = await MainActor.run {
            guard let walkUUID = walk.uuid,
                  let dbWalk = try? DataManager.dataStack.fetchOne(
                    From<Walk>().where(\._uuid == walkUUID)
                  ) else {
                return walk.voiceRecordings
            }
            return dbWalk.voiceRecordings
        }

        for (index, recording) in freshRecordings.enumerated() {
            let audioURL = docs.appendingPathComponent(recording.fileRelativePath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }

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

        guard !uploadedRecordings.isEmpty else {
            throw SubmissionError.noRecordingsFound
        }

        try await submitMetadata(
            walk: walk,
            submissionId: submissionId,
            recordings: uploadedRecordings,
            deviceToken: deviceToken,
            shareURL: shareURL,
            reflection: reflection
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
        deviceToken: String,
        shareURL: String?,
        reflection: String?
    ) async throws {
        let first = walk.routeData.first
        var weather: String?
        if let condition = walk.weatherCondition {
            weather = condition
            if let temp = walk.weatherTemperature {
                weather = "\(condition), \(Int(temp))\u{00B0}C"
            }
        }

        var metadata: [String: Any] = [
            "distance_km": walk.distance / 1000,
            "active_duration": walk.activeDuration,
            "talk_duration": walk.talkDuration,
            "meditate_duration": walk.meditateDuration,
            "date": Self.dateString(for: walk.startDate),
        ]
        if let weather { metadata["weather"] = weather }
        if let intention = walk.comment { metadata["intention"] = intention }
        if let lat = first?.latitude, let lon = first?.longitude {
            metadata["start_lat"] = lat
            metadata["start_lon"] = lon
            metadata["location"] = String(format: "%.4f, %.4f", lat, lon)
        }
        if let shareURL { metadata["share_url"] = shareURL }
        if let reflection { metadata["reflection"] = reflection }

        let payload: [String: Any] = [
            "submission_id": submissionId,
            "metadata": metadata,
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static func todayString() -> String {
        dayFormatter.string(from: Date())
    }

    private static func dateString(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    enum SubmissionError: LocalizedError {
        case uploadFailed(String)
        case submissionFailed
        case noRecordingsFound

        var errorDescription: String? {
            switch self {
            case .uploadFailed(let name): return "Failed to upload \(name)."
            case .submissionFailed: return "Failed to submit walk."
            case .noRecordingsFound: return "No audio files found on this device."
            }
        }
    }
}
