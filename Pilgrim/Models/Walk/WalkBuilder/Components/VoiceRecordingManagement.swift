import Foundation
import AVFoundation
import Combine
import CombineExt

public class VoiceRecordingManagement: NSObject, WalkBuilderComponent {

    private var audioRecorder: AVAudioRecorder?
    private var isWalkActive = false
    private var currentRecordingStart: Date?
    private var currentRecordingRelativePath: String?
    private var walkUUID = UUID()

    private var cancellables: [AnyCancellable] = []
    private weak var builder: WalkBuilder?

    private let voiceRecordingsRelay = CurrentValueRelay<[TempVoiceRecording]>([])

    @Published public private(set) var isRecording = false
    @Published public private(set) var recordingStartDate: Date?
    @Published public private(set) var audioLevel: Float = 0

    private var meteringTimer: Timer?

    public required init(builder: WalkBuilder) {
        super.init()
        self.builder = builder
        bind(builder: builder)

        builder.registerPreSnapshotFlush { [weak self] in
            self?.flushCurrentRecording()
        }
    }

    public func bind(builder: WalkBuilder) {
        let input = WalkBuilder.Input(
            voiceRecordings: voiceRecordingsRelay.asBackgroundPublisher()
        )
        _ = builder.tranform(input)

        builder.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isWalkActive = status.isActiveStatus
            }.store(in: &cancellables)

        builder.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.voiceRecordingsRelay.accept([])
                self.walkUUID = UUID()
            }.store(in: &cancellables)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("[VoiceRecordingManagement] Failed to configure audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func ensureRecordingsDirectory() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Recordings/\(walkUUID.uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            print("[VoiceRecordingManagement] Failed to create recordings directory: \(error)")
            return nil
        }
    }

    public func startRecording() {
        guard isWalkActive, !isRecording else { return }

        configureAudioSession()

        guard let dir = ensureRecordingsDirectory() else { return }

        let recordingID = UUID()
        let filename = "\(recordingID.uuidString).m4a"
        let fileURL = dir.appendingPathComponent(filename)
        let relativePath = "Recordings/\(walkUUID.uuidString)/\(filename)"

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            let now = Date()
            currentRecordingStart = now
            currentRecordingRelativePath = relativePath
            recordingStartDate = now
            isRecording = true
            startMetering()
        } catch {
            print("[VoiceRecordingManagement] Failed to start recording: \(error)")
            deactivateAudioSession()
        }
    }

    public func stopRecording() {
        guard isRecording, let recorder = audioRecorder else { return }
        stopMetering()
        recorder.stop()
        isRecording = false
        recordingStartDate = nil
        audioRecorder = nil
    }

    private func flushCurrentRecording() {
        guard isRecording, let recorder = audioRecorder else {
            builder?.flushVoiceRecordings(voiceRecordingsRelay.value)
            return
        }
        stopMetering()
        isRecording = false
        recordingStartDate = nil
        audioRecorder = nil
        recorder.delegate = nil
        recorder.stop()
        commitRecording(successfully: true)
        builder?.flushVoiceRecordings(voiceRecordingsRelay.value)
    }

    private func commitRecording(successfully flag: Bool) {
        guard let start = currentRecordingStart, let relativePath = currentRecordingRelativePath else {
            return
        }

        defer {
            currentRecordingStart = nil
            currentRecordingRelativePath = nil
            deactivateAudioSession()
        }

        guard flag else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = docs.appendingPathComponent(relativePath)
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let end = Date()
        let recording = TempVoiceRecording(
            uuid: UUID(),
            startDate: start,
            endDate: end,
            duration: end.timeIntervalSince(start),
            fileRelativePath: relativePath
        )
        voiceRecordingsRelay.accept(voiceRecordingsRelay.value + [recording])
    }

    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            self.audioLevel = max(0, min(1, (power + 50) / 50))
        }
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        audioLevel = 0
    }

    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
}

extension VoiceRecordingManagement: AVAudioRecorderDelegate {

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        commitRecording(successfully: flag)
    }
}
