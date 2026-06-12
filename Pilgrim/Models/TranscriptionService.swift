import Foundation
import WhisperKit
import CoreStore

/// Result of transcribing one audio file, expressed in domain terms so
/// tests can fake the engine without importing WhisperKit.
struct TranscriptionOutput {
    let text: String
    let wordsPerMinute: Double?
}

/// Seam over WhisperKit — the one surface through which the service
/// touches the loaded model, so lifecycle behavior (load, batch, unload)
/// is testable without a real CoreML model.
protocol TranscriptionEngine: AnyObject {
    func transcribeAudio(atPath path: String) async throws -> TranscriptionOutput
    func unloadModels() async
}

extension WhisperKit: TranscriptionEngine {

    func transcribeAudio(atPath path: String) async throws -> TranscriptionOutput {
        let results = try await transcribe(audioPath: path)
        return TranscriptionOutput(
            text: results.map(\.text).joined(separator: " "),
            wordsPerMinute: Self.wordsPerMinute(from: results)
        )
    }

    private static func wordsPerMinute(from results: [TranscriptionResult]) -> Double? {
        let segments = results.flatMap { $0.segments }
        guard let first = segments.first, let last = segments.last,
              last.end > first.start else { return nil }
        let words = segments.compactMap { $0.words }.flatMap { $0 }
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
}

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

    private var whisperKit: TranscriptionEngine?
    private let modelVariant = "tiny"

    /// Singleton in production; internal so tests can construct isolated
    /// instances without touching `shared` state.
    init() {}

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
        var persistenceFailures = 0
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
            guard !recording.fileRelativePath.isEmpty else { continue }

            await MainActor.run { state = .transcribing(current: index + 1, total: total) }

            let audioURL = docs.appendingPathComponent(recording.fileRelativePath)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }

            do {
                let output = try await pipe.transcribeAudio(atPath: audioURL.path)
                let text = cleanTranscription(output.text)
                if !text.isEmpty {
                    if await persistTranscription(uuid: uuid, text: text) {
                        results[uuid] = text
                        if let wpm = output.wordsPerMinute {
                            await persistWordsPerMinute(uuid: uuid, wordsPerMinute: wpm)
                        }
                    } else {
                        // Leaving the recording untranscribed keeps it in the
                        // next auto-transcribe pass's selection — the work is
                        // re-attempted instead of silently lost.
                        persistenceFailures += 1
                    }
                }
            } catch {
                print("[TranscriptionService] Failed to transcribe recording \(uuid): \(error)")
            }
        }

        let finalState: State = persistenceFailures == 0
            ? .completed
            : .failed("Couldn't save \(persistenceFailures) transcription\(persistenceFailures == 1 ? "" : "s")")
        await MainActor.run {
            state = finalState
            isTranscribing = false
            unloadModel()
        }
        return results
    }

    func transcribeSingle(_ recording: VoiceRecordingInterface) async -> String? {
        guard let uuid = recording.uuid else { return nil }
        guard !recording.fileRelativePath.isEmpty else { return nil }
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
            let output = try await pipe.transcribeAudio(atPath: audioURL.path)
            let text = cleanTranscription(output.text)
            guard !text.isEmpty else {
                await MainActor.run { state = .completed; isTranscribing = false }
                return nil
            }
            guard await persistTranscription(uuid: uuid, text: text) else {
                await MainActor.run { state = .failed("Transcription couldn't be saved"); isTranscribing = false }
                return nil
            }
            if let wpm = output.wordsPerMinute {
                await persistWordsPerMinute(uuid: uuid, wordsPerMinute: wpm)
            }
            await MainActor.run { state = .completed; isTranscribing = false }
            return text
        } catch {
            print("[TranscriptionService] Failed to transcribe: \(error)")
            await MainActor.run { state = .failed("Transcription failed"); isTranscribing = false }
            return nil
        }
    }

    /// Persists a transcription with one retry. Returns `false` when the
    /// write failed (or the recording row is gone) so callers can avoid
    /// reporting unsaved work as done.
    private func persistTranscription(uuid: UUID, text: String) async -> Bool {
        if await persistTranscriptionOnce(uuid: uuid, text: text) { return true }
        if await persistTranscriptionOnce(uuid: uuid, text: text) { return true }
        print("[TranscriptionService] Transcription for \(uuid) not saved after retry")
        return false
    }

    private func persistTranscriptionOnce(uuid: UUID, text: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DataManager.updateVoiceRecordingTranscription(uuid: uuid, transcription: text) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// WPM is a derived nicety — a final failure is logged but does not
    /// fail the transcription, which is already persisted at this point.
    private func persistWordsPerMinute(uuid: UUID, wordsPerMinute: Double) async {
        for _ in 0..<2 {
            let saved = await withCheckedContinuation { continuation in
                DataManager.updateVoiceRecordingWordsPerMinute(uuid: uuid, wordsPerMinute: wordsPerMinute) { success in
                    continuation.resume(returning: success)
                }
            }
            if saved { return }
        }
        print("[TranscriptionService] WPM for \(uuid) not saved after retry")
    }

    private static let whisperArtifacts = ["[BLANK_AUDIO]", "[NO_SPEECH]", "(blank_audio)", "(no_speech)"]

    private func cleanTranscription(_ text: String) -> String {
        var cleaned = text
        for artifact in Self.whisperArtifacts {
            cleaned = cleaned.replacingOccurrences(of: artifact, with: "")
        }
        return cleaned
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            await MainActor.run { isTranscribing = false; unloadModel() }
            return nil
        }

        do {
            let output = try await pipe.transcribeAudio(atPath: url.path)
            let text = cleanTranscription(output.text)
            await MainActor.run { isTranscribing = false; unloadModel() }
            return text.isEmpty ? nil : text
        } catch {
            await MainActor.run { isTranscribing = false; unloadModel() }
            return nil
        }
    }

    /// Releases the WhisperKit pipeline once a transcription flow drains
    /// (AF33) — tens of MB of CoreML state would otherwise stay resident
    /// through multi-hour walks. No-op while a batch is active, and leaves
    /// `state` untouched so completion/failure UI isn't reset.
    @MainActor
    func unloadModel() {
        guard !isTranscribing else { return }
        guard let kit = whisperKit else { return }
        whisperKit = nil
        Task.detached { await kit.unloadModels() }
    }

    enum AutoTranscriptionSkipReason {
        case lowBattery
    }

    @MainActor @Published var autoTranscriptionSkippedReason: AutoTranscriptionSkipReason?

    // MARK: - Test Hooks

    #if DEBUG
    @MainActor
    func _test_setEngine(_ engine: TranscriptionEngine?) {
        whisperKit = engine
    }

    @MainActor
    func _test_setTranscribing(_ value: Bool) {
        isTranscribing = value
    }

    @MainActor
    var _test_isModelLoaded: Bool { whisperKit != nil }
    #endif

}
