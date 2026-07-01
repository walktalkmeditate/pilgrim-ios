import Foundation
import AVFoundation
import CallKit
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
    private let callObserver: CXCallObserver = CXCallObserver()

    public required init(builder: WalkBuilder) {
        super.init()
        self.builder = builder
        bind(builder: builder)

        builder.registerPreSnapshotFlush { [weak self] in
            self?.flushCurrentRecording()
        }

        callObserver.setDelegate(self, queue: .main)

        audioCoordinator.addInterruptionObserver(id: "voiceRecording") { [weak self] event in
            self?.handleAudioInterruption(event)
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

    private let audioCoordinator = AudioSessionCoordinator.shared

    private func configureAudioSession() {
        // The coordinator arbitrates the actual session category: if any
        // playback consumer (soundscape, whisper, bell) is live, this
        // recordingOnly request resolves to recordAndPlay automatically.
        audioCoordinator.activate(for: .recordingOnly, consumer: "voiceRecording")
    }

    private func deactivateAudioSession() {
        audioCoordinator.deactivate(consumer: "voiceRecording")
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

        VoiceGuidePlayer.shared.stop()

        // Activate only once the directory exists — the early return must
        // not leave the "voiceRecording" consumer holding a mic-active
        // session it will never release.
        guard let dir = ensureRecordingsDirectory() else { return }

        configureAudioSession()

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
        // Relaxed from `guard isRecording, let recorder = audioRecorder` to
        // tolerate the #if DEBUG _test_setActiveRecording path, which sets
        // isRecording=true without a real AVAudioRecorder. In production
        // these flags always move together — see startRecording /
        // flushCurrentRecording / commitRecording.
        guard isRecording else { return }
        stopMetering()
        audioRecorder?.stop()
        isRecording = false
        recordingStartDate = nil
        audioRecorder = nil
    }

    private func flushCurrentRecording() {
        guard isRecording, audioRecorder != nil else {
            builder?.flushVoiceRecordings(voiceRecordingsRelay.value)
            return
        }
        commitActiveRecordingAndReset()
        builder?.flushVoiceRecordings(voiceRecordingsRelay.value)
    }

    /// Stop the recorder, commit the audio captured so far, and clear all
    /// recording state. The delegate is detached before stopping so the commit
    /// runs exactly once here, not again via `audioRecorderDidFinishRecording`.
    /// Tolerates a nil `audioRecorder` for the test-injected recording path.
    private func commitActiveRecordingAndReset() {
        stopMetering()
        isRecording = false
        recordingStartDate = nil
        audioRecorder?.delegate = nil
        audioRecorder?.stop()
        audioRecorder = nil
        commitRecording(successfully: true)
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
        let recordingUUID = UUID()
        // isEnhanced is finalized as false and flipped only after
        // VoiceEnhancer reports success — the flag must never claim an
        // enhancement that failed (it round-trips through checkpoints
        // and exports).
        finalizeRecording(uuid: recordingUUID, start: start, end: end, relativePath: relativePath)

        if UserPreferences.dynamicVoiceEnabled.value {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = docs.appendingPathComponent(relativePath)
            VoiceEnhancer.shared.enhance(fileURL) { [weak self] success in
                guard success else {
                    print("[VoiceRecordingManagement] Enhancement failed — recording \(recordingUUID) stays raw")
                    return
                }
                self?.markRecordingEnhanced(uuid: recordingUUID)
            }
        }
    }

    private func finalizeRecording(uuid: UUID, start: Date, end: Date, relativePath: String) {
        let recording = TempVoiceRecording(
            uuid: uuid,
            startDate: start,
            endDate: end,
            duration: end.timeIntervalSince(start),
            fileRelativePath: relativePath,
            isEnhanced: false
        )
        voiceRecordingsRelay.accept(voiceRecordingsRelay.value + [recording])
    }

    /// Runs on the main queue (VoiceEnhancer completes there). If the walk
    /// is still in progress the relay entry is updated in place; if it was
    /// already saved (relay reset on walk completion), the persisted row is
    /// updated instead — `persistVoiceRecordings` preserves the temp UUID.
    private func markRecordingEnhanced(uuid: UUID) {
        let current = voiceRecordingsRelay.value
        if let match = current.first(where: { $0.uuid == uuid }) {
            match.isEnhanced = true
            voiceRecordingsRelay.accept(current)
        } else {
            DataManager.updateVoiceRecordingIsEnhanced(uuid: uuid, isEnhanced: true)
        }
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

    /// Returns a provisional `TempVoiceRecording` capturing the currently-active
    /// recording's start + elapsed duration so far, or `nil` if no recording is
    /// active. Mirrors the meditation-interval provisional pattern in
    /// `ActiveWalkViewModel.checkpointActivityIntervals()`. The returned recording
    /// has the real in-flight file path; on recovery, the file may or may not be
    /// playable depending on whether AVAudioRecorder wrote its moov atom before
    /// the process died.
    public func checkpointVoiceRecording() -> TempVoiceRecording? {
        guard isRecording,
              let start = currentRecordingStart,
              let relativePath = currentRecordingRelativePath else {
            return nil
        }
        let now = Date()
        return TempVoiceRecording(
            uuid: nil,
            startDate: start,
            endDate: now,
            duration: now.timeIntervalSince(start),
            fileRelativePath: relativePath,
            isEnhanced: false
        )
    }

    #if DEBUG
    /// Overrides `recorderStillCapturing` in tests, where no real AVAudioRecorder
    /// exists to report its state.
    private var testRecorderCapturingOverride: Bool?

    /// Test-only hook. Sets the internal state that `startRecording()` would set
    /// without requiring AVAudioSession permission in the unit-test environment.
    func _test_setActiveRecording(start: Date, relativePath: String) {
        currentRecordingStart = start
        currentRecordingRelativePath = relativePath
        recordingStartDate = start
        isRecording = true
    }

    /// Test-only hook. Simulates whether the underlying recorder survived an
    /// interruption (true) or was stopped by it (false).
    func _test_setRecorderCapturing(_ capturing: Bool) {
        testRecorderCapturingOverride = capturing
    }
    #endif
}

extension VoiceRecordingManagement: AVAudioRecorderDelegate {

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // An OS-driven finish (encoder failure, hardware/route loss) can fire
        // while our flags still say "recording". Reset them so the UI doesn't
        // show a live talk backed by a dead recorder, and the walk-end flush
        // can't silently drop an already-finalized file.
        if isRecording {
            stopMetering()
            isRecording = false
            recordingStartDate = nil
            audioRecorder = nil
        }
        commitRecording(successfully: flag)
    }
}

extension VoiceRecordingManagement: CXCallObserverDelegate {

    public func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
        handleCallStateChange(hasEnded: call.hasEnded)
    }

    /// A phone call — incoming-ringing, connected, or outgoing — takes the mic,
    /// so the talk must stop. CXCallObserver reports any active call here
    /// (`!hasEnded`), which is the reliable signal; an *unanswered* incoming
    /// call (rings, never connects) is caught this way too. There is deliberately
    /// no `hasConnected` gate — we do not wait for the call to connect. Only an
    /// actual call ends the talk — see `handleAudioInterruption` for why
    /// transient (non-call) interruptions deliberately do not.
    private func handleCallStateChange(hasEnded: Bool) {
        guard !hasEnded, isRecording else { return }
        stopRecording()
    }

    /// A transient interruption (a notification sound, Siri, an alarm) must not
    /// end a talk the recorder lives through, so we never finalize on `.began`.
    /// But an `AVAudioRecorder` the system actually paused cannot resume into the
    /// same file (Apple-confirmed), so when the interruption ends we check
    /// whether the recorder kept capturing: if it did, the talk continues
    /// untouched; if it was stopped, we finalize the audio captured so far and
    /// release the mic — rather than holding a live session that records nothing
    /// for the rest of the walk and stamps an inflated duration at walk end.
    /// Real phone calls are handled by CXCallObserver above, not here. No new
    /// recording is started: the talk stays a single file instead of splitting.
    private func handleAudioInterruption(_ event: AudioSessionCoordinator.InterruptionEvent) {
        guard isRecording else { return }
        switch event {
        case .began:
            return
        case .ended:
            guard !recorderStillCapturing else { return }
            print("[VoiceRecordingManagement] interruption ended with a stopped recorder — finalizing captured audio")
            commitActiveRecordingAndReset()
        }
    }

    /// Whether the underlying recorder is still actively capturing. After a
    /// system interruption that paused it, this reads false and the file can no
    /// longer be resumed. Overridable under test, where no real AVAudioRecorder
    /// is created.
    private var recorderStillCapturing: Bool {
        #if DEBUG
        if let override = testRecorderCapturingOverride { return override }
        #endif
        return audioRecorder?.isRecording ?? false
    }

    #if DEBUG
    func _test_simulateCallChanged(hasEnded: Bool) {
        handleCallStateChange(hasEnded: hasEnded)
    }

    func _test_simulateAudioInterruption(_ event: AudioSessionCoordinator.InterruptionEvent) {
        handleAudioInterruption(event)
    }
    #endif
}
