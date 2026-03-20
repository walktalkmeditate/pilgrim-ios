import Foundation
import Combine

enum SchedulerContext {
    case walk
    case meditation
}

final class VoiceGuideScheduler {

    struct WalkState {
        var status: WalkBuilder.Status = .waiting
        var isRecordingVoice = false
        var isMeditating = false
        var walkStartDate: Date?
    }

    private let prompts: [VoiceGuidePrompt]
    private let scheduling: PromptDensity
    private let context: SchedulerContext
    private let settlingThresholdSec: TimeInterval
    private let closingThresholdSec: TimeInterval
    private var startDate: Date?

    private var cancellables: [AnyCancellable] = []

    private var walkState = WalkState()
    private var isPaused = false
    private var isPlaying = false
    private var lastPromptTime: Date?
    private var nextIntervalSec: TimeInterval = 0
    private(set) var playedPromptIds: Set<String> = []
    private var silenceUntil: Date?

    var onShouldPlay: ((VoiceGuidePrompt) -> Void)?

    init(
        prompts: [VoiceGuidePrompt],
        scheduling: PromptDensity,
        context: SchedulerContext = .walk,
        startDate: Date? = nil,
        settlingThresholdSec: TimeInterval = 20 * 60,
        closingThresholdSec: TimeInterval = 45 * 60
    ) {
        self.prompts = prompts
        self.scheduling = scheduling
        self.context = context
        self.startDate = startDate
        self.settlingThresholdSec = settlingThresholdSec
        self.closingThresholdSec = closingThresholdSec
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

    func setPostMeditationSilence() {
        let buffer = TimeInterval(Int.random(in: 600...900))
        silenceUntil = Date().addingTimeInterval(buffer)
    }

    func testTick() { tick() }

    private func tick() {
        switch context {
        case .walk:
            guard walkState.status == .recording,
                  !walkState.isRecordingVoice,
                  !walkState.isMeditating,
                  !isPaused,
                  !isPlaying else { return }
        case .meditation:
            guard !isPaused, !isPlaying else { return }
        }

        if let silenceUntil, Date() < silenceUntil { return }

        let effectiveStartDate: Date?
        switch context {
        case .walk: effectiveStartDate = walkState.walkStartDate
        case .meditation: effectiveStartDate = startDate
        }

        guard let startDate = effectiveStartDate else { return }

        let elapsed = Date().timeIntervalSince(startDate)
        guard elapsed >= TimeInterval(scheduling.initialDelaySec) else { return }

        if let lastTime = lastPromptTime {
            let sinceLast = Date().timeIntervalSince(lastTime)
            guard sinceLast >= nextIntervalSec else { return }
        }

        guard let prompt = nextPrompt(elapsed: elapsed) else { return }

        markPlaybackStarted()
        onShouldPlay?(prompt)
    }

    private func nextPrompt(elapsed: TimeInterval) -> VoiceGuidePrompt? {
        let currentPhase = phase(for: elapsed)
        let sorted = prompts.sorted { $0.seq < $1.seq }

        let phaseFiltered = sorted.filter { prompt in
            guard let promptPhase = prompt.phase else { return true }
            return promptPhase == currentPhase.rawValue
        }

        let pool = phaseFiltered.isEmpty ? sorted : phaseFiltered

        if let unplayed = pool.first(where: { !playedPromptIds.contains($0.id) }) {
            return unplayed
        }

        let allUnplayed = sorted.first(where: { !playedPromptIds.contains($0.id) })
        if let fallback = allUnplayed {
            return fallback
        }

        playedPromptIds.removeAll()
        return pool.first
    }

    private func phase(for elapsed: TimeInterval) -> PromptPhase {
        if elapsed < settlingThresholdSec {
            return .settling
        } else if elapsed >= closingThresholdSec {
            return .closing
        }
        return .deepening
    }

    private func drawNextInterval() {
        let min = scheduling.densityMinSec
        let max = scheduling.densityMaxSec
        nextIntervalSec = TimeInterval(Int.random(in: min...max))
    }
}
