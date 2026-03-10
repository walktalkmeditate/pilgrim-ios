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

    private var modelStoragePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WhisperModels")
    }

    var isModelDownloaded: Bool {
        guard FileManager.default.fileExists(atPath: modelStoragePath.path) else { return false }
        guard let modelDir = modelDirectory else { return false }
        let modelFiles = (try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)) ?? []
        return !modelFiles.isEmpty
    }

    private var modelDirectory: URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(at: modelStoragePath, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents.first { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir && url.lastPathComponent.hasPrefix("openai_whisper-\(modelVariant)")
        }
    }

    func ensureModelReady() async throws {
        if whisperKit != nil { return }

        await MainActor.run { state = .downloadingModel(progress: 0) }

        let modelsDir = modelStoragePath

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        let modelURL: URL
        if let existing = modelDirectory {
            modelURL = existing
        } else {
            modelURL = try await downloadModel(to: modelsDir)
        }

        let config = WhisperKitConfig(
            modelFolder: modelURL.path,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)

        await MainActor.run { state = .idle }
    }

    private func downloadModel(to modelsDir: URL) async throws -> URL {
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
                return text
            }
            return nil
        } catch {
            print("[TranscriptionService] Failed to transcribe: \(error)")
            await MainActor.run { state = .failed("Transcription failed"); isTranscribing = false }
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
}
