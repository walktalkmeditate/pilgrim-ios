import Foundation
import Combine

final class VoiceGuideScheduler {

    struct WalkState {
        var status: WalkBuilder.Status = .waiting
        var isRecordingVoice = false
        var isMeditating = false
        var walkStartDate: Date?
    }

    private let pack: VoiceGuidePack
    private let fileStore = VoiceGuideFileStore.shared
    private var cancellables: [AnyCancellable] = []

    private var walkState = WalkState()
    private var isPaused = false
    private var isPlaying = false
    private var lastPromptTime: Date?
    private var nextIntervalSec: TimeInterval = 0
    private(set) var playedPromptIds: Set<String> = []

    var onShouldPlay: ((VoiceGuidePrompt) -> Void)?

    init(pack: VoiceGuidePack) {
        self.pack = pack
        drawNextInterval()
    }

    func start() {
        Timer.TimerPublisher(interval: 30, runLoop: .main, mode: .default)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func updateStatus(_ status: WalkBuilder.Status) {
        walkState.status = status
    }

    func updateIsRecordingVoice(_ recording: Bool) {
        walkState.isRecordingVoice = recording
    }

    func updateIsMeditating(_ meditating: Bool) {
        walkState.isMeditating = meditating
    }

    func updateWalkStartDate(_ date: Date?) {
        walkState.walkStartDate = date
    }

    func markPlayed(_ promptId: String) {
        playedPromptIds.insert(promptId)
        lastPromptTime = Date()
        isPlaying = false
        drawNextInterval()
    }

    func setPlayedHistory(_ ids: Set<String>) {
        playedPromptIds = ids
    }

    func markPlaybackStarted() {
        isPlaying = true
    }

    private func tick() {
        guard walkState.status == .recording,
              !walkState.isRecordingVoice,
              !walkState.isMeditating,
              !isPaused,
              !isPlaying else { return }

        guard let startDate = walkState.walkStartDate else { return }

        let elapsed = Date().timeIntervalSince(startDate)
        guard elapsed >= TimeInterval(pack.scheduling.initialDelaySec) else { return }

        if let lastTime = lastPromptTime {
            let sinceLast = Date().timeIntervalSince(lastTime)
            guard sinceLast >= nextIntervalSec else { return }
        }

        guard let prompt = nextPrompt() else { return }
        guard fileStore.isAvailable(prompt, packId: pack.id) else { return }

        markPlaybackStarted()
        onShouldPlay?(prompt)
    }

    private func nextPrompt() -> VoiceGuidePrompt? {
        let sorted = pack.prompts.sorted { $0.seq < $1.seq }
        if let unplayed = sorted.first(where: { !playedPromptIds.contains($0.id) }) {
            return unplayed
        }
        playedPromptIds.removeAll()
        return sorted.first
    }

    private func drawNextInterval() {
        let min = pack.scheduling.densityMinSec
        let max = pack.scheduling.densityMaxSec
        nextIntervalSec = TimeInterval(Int.random(in: min...max))
    }
}
