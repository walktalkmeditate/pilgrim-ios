import AVFoundation
import Combine

final class IntentionVoiceRecorder: NSObject, ObservableObject {

    static let maxDuration: TimeInterval = 30

    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var timeRemaining: TimeInterval = maxDuration
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedText: String?

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var countdownTimer: Timer?
    private var countdownGeneration = 0
    private var recordingURL: URL?

    override init() {
        super.init()
    }

    deinit {
        cleanup()
    }

    func startRecording() {
        guard !isRecording else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("intention_\(UUID().uuidString).m4a")

        AudioSessionCoordinator.shared.activate(for: .recordingOnly, consumer: "intentionRecorder")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            recordingURL = url
            isRecording = true
            timeRemaining = Self.maxDuration
            startMetering()
            startCountdown()
        } catch {
            AudioSessionCoordinator.shared.deactivate(consumer: "intentionRecorder")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        stopTimers()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        AudioSessionCoordinator.shared.deactivate(consumer: "intentionRecorder")
    }

    func transcribe() async -> String? {
        guard let url = recordingURL else { return nil }
        await MainActor.run { isTranscribing = true }
        let result = await TranscriptionService.shared.transcribeAudioFile(at: url)
        await MainActor.run {
            isTranscribing = false
            transcribedText = result
        }
        return result
    }

    func cancel() {
        stopTimers()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        isTranscribing = false
        transcribedText = nil
        AudioSessionCoordinator.shared.deactivate(consumer: "intentionRecorder")
        deleteTempFile()
    }

    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            self.audioLevel = max(0, min(1, (power + 50) / 50))
        }
    }

    private func startCountdown() {
        countdownGeneration += 1
        let generation = countdownGeneration
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.countdownGeneration == generation else { return }
            self.timeRemaining -= 1
            if self.timeRemaining <= 0 {
                self.stopRecording()
            }
        }
    }

    private func stopTimers() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        audioLevel = 0
    }

    private func deleteTempFile() {
        guard let url = recordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
    }

    private func cleanup() {
        stopTimers()
        audioRecorder?.stop()
        audioRecorder = nil
        AudioSessionCoordinator.shared.deactivate(consumer: "intentionRecorder")
        deleteTempFile()
    }
}

extension IntentionVoiceRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            deleteTempFile()
        }
    }
}
