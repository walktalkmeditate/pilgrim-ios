import Foundation
import WhisperKit
import CoreStore

final class TranscriptionService: ObservableObject {

    static let shared = TranscriptionService()

    enum State: Equatable {
        case idle
        case downloadingModel(progress: Double)
        case transcribing(current: Int, total: Int)
        case completed
        case failed(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.completed, .completed): return true
            case (.downloadingModel(let a), .downloadingModel(let b)): return a == b
            case (.transcribing(let a1, let a2), .transcribing(let b1, let b2)): return a1 == b1 && a2 == b2
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    @MainActor @Published var state: State = .idle
    @MainActor private var isTranscribing = false

    private var whisperKit: WhisperKit?
    private let modelVariant = "tiny"

    private init() {}

    private var savedModelPath: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: "whisperModelPath") else { return nil }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: "whisperModelPath")
        }
    }

    var isModelDownloaded: Bool {
        guard let modelDir = savedModelPath else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)) ?? []
        return !files.isEmpty
    }

    func ensureModelReady() async throws {
        if whisperKit != nil { return }

        await MainActor.run { state = .downloadingModel(progress: 0) }

        let modelURL: URL
        if let existing = savedModelPath {
            modelURL = existing
        } else {
            modelURL = try await downloadModel()
            savedModelPath = modelURL
        }

        let config = WhisperKitConfig(
            modelFolder: modelURL.path,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)

        await MainActor.run { state = .idle }
    }

    private func downloadModel() async throws -> URL {
        try await WhisperKit.download(
            variant: modelVariant,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.state = .downloadingModel(progress: progress.fractionCompleted)
                }
            }
        )
    }

    func transcribeRecordings(_ recordings: [VoiceRecordingInterface]) async -> [UUID: String] {
        guard !recordings.isEmpty else { return [:] }
        let started = await MainActor.run { () -> Bool in
            guard !isTranscribing else { return false }
            isTranscribing = true
            state = .idle
            return true
        }
        guard started else { return [:] }

        var results: [UUID: String] = [:]
        let total = recordings.count

        do {
            try await ensureModelReady()
        } catch {
            await MainActor.run { state = .failed("Model setup failed: \(error.localizedDescription)"); isTranscribing = false }
            return [:]
        }

        guard let pipe = whisperKit else {
            await MainActor.run { state = .failed("WhisperKit not initialized"); isTranscribing = false }
            return [:]
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        for (index, recording) in recordings.enumerated() {
            guard let uuid = recording.uuid else { continue }

            await MainActor.run { state = .transcribing(current: index + 1, total: total) }

            let audioURL = docs.appendingPathComponent(recording.fileRelativePath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }

            do {
                let transcriptionResults = try await pipe.transcribe(audioPath: audioURL.path)
                let text = transcriptionResults.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    results[uuid] = text
                    DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: text)
                    if let wpm = computeWordsPerMinute(from: transcriptionResults) {
                        DataManager.updateVoiceRecordingWordsPerMinute(uuid: uuid, wordsPerMinute: wpm)
                    }
                }
            } catch {
                print("[TranscriptionService] Failed to transcribe recording \(uuid): \(error)")
            }
        }

        await MainActor.run { state = .completed; isTranscribing = false }
        return results
    }

    func transcribeSingle(_ recording: VoiceRecordingInterface) async -> String? {
        guard let uuid = recording.uuid else { return nil }
        let started = await MainActor.run { () -> Bool in
            guard !isTranscribing else { return false }
            isTranscribing = true
            state = .idle
            return true
        }
        guard started else { return nil }

        do {
            try await ensureModelReady()
        } catch {
            await MainActor.run { state = .failed("Model setup failed: \(error.localizedDescription)"); isTranscribing = false }
            return nil
        }

        guard let pipe = whisperKit else {
            await MainActor.run { isTranscribing = false }
            return nil
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioURL = docs.appendingPathComponent(recording.fileRelativePath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            await MainActor.run { isTranscribing = false }
            return nil
        }

        await MainActor.run { state = .transcribing(current: 1, total: 1) }

        do {
            let results = try await pipe.transcribe(audioPath: audioURL.path)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { state = .completed; isTranscribing = false }
            if !text.isEmpty {
                DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: text)
                if let wpm = computeWordsPerMinute(from: results) {
                    DataManager.updateVoiceRecordingWordsPerMinute(uuid: uuid, wordsPerMinute: wpm)
                }
                return text
            }
            return nil
        } catch {
            print("[TranscriptionService] Failed to transcribe: \(error)")
            await MainActor.run { state = .failed("Transcription failed"); isTranscribing = false }
            return nil
        }
    }

    private func computeWordsPerMinute(from results: [TranscriptionResult]) -> Double? {
        let segments = results.flatMap { $0.segments }
        guard let first = segments.first, let last = segments.last,
              last.end > first.start else { return nil }
        let words = segments.flatMap { $0.words }
        let wordCount: Int
        if !words.isEmpty {
            wordCount = words.count
        } else {
            wordCount = segments.flatMap { $0.text.split(separator: " ") }.count
        }
        guard wordCount > 0 else { return nil }
        let durationMinutes = Double(last.end - first.start) / 60.0
        guard durationMinutes > 0 else { return nil }
        return Double(wordCount) / durationMinutes
    }

    func transcribeAudioFile(at url: URL) async -> String? {
        let started = await MainActor.run { () -> Bool in
            guard !isTranscribing else { return false }
            isTranscribing = true
            return true
        }
        guard started else { return nil }

        do {
            try await ensureModelReady()
        } catch {
            await MainActor.run { isTranscribing = false }
            return nil
        }

        guard let pipe = whisperKit,
              FileManager.default.fileExists(atPath: url.path) else {
            await MainActor.run { isTranscribing = false }
            return nil
        }

        do {
            let results = try await pipe.transcribe(audioPath: url.path)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { isTranscribing = false }
            return text.isEmpty ? nil : text
        } catch {
            await MainActor.run { isTranscribing = false }
            return nil
        }
    }

    @MainActor
    func unloadModel() {
        let kit = whisperKit
        whisperKit = nil
        state = .idle
        Task.detached { await kit?.unloadModels() }
    }

    enum AutoTranscriptionSkipReason {
        case lowBattery
    }

    @MainActor @Published var autoTranscriptionSkippedReason: AutoTranscriptionSkipReason?

}
