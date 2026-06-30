import Foundation
import Combine

final class VoiceGuideManagement: ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var isPaused = false

    private var scheduler: VoiceGuideScheduler?
    private let player = VoiceGuidePlayer.shared
    private var walkStateBindings: [AnyCancellable] = []
    private var schedulerCancellables: [AnyCancellable] = []
    private var generation = 0
    private var currentPackId: String?
    private var wasPausedByMeditation = false

    var packName: String? {
        guard isActive, let packId = currentPackId else { return nil }
        return VoiceGuideManifestService.shared.pack(byId: packId)?.name
    }

    var hasLastPrompt: Bool { player.hasLastPrompt }

    private var lastKnownWalkStartDate: Date?
    private var lastKnownWalkStatus: WalkBuilder.Status = .waiting

    func startGuiding(pack: VoiceGuidePack) {
        stopGuiding()

        generation += 1
        let capturedGeneration = generation
        currentPackId = pack.id

        let sched = VoiceGuideScheduler(
            prompts: pack.prompts,
            scheduling: pack.scheduling,
            context: .walk
        )
        sched.setPlayedHistory(loadHistory(for: pack.id))
        sched.onShouldPlay = { [weak self] prompt in
            self?.playPrompt(prompt, packId: pack.id, generation: capturedGeneration)
        }
        if let startDate = lastKnownWalkStartDate {
            sched.updateWalkStartDate(startDate)
        }
        sched.updateStatus(lastKnownWalkStatus)
        scheduler = sched
        isActive = true
        isPaused = false
        wasPausedByMeditation = false

        sched.start()
    }

    func stopGuiding() {
        scheduler?.stop()
        player.stop()
        if let packId = currentPackId, let scheduler {
            persistHistory(for: packId, scheduler: scheduler)
        }
        scheduler = nil
        schedulerCancellables.removeAll()
        isActive = false
        isPaused = false
        wasPausedByMeditation = false
        currentPackId = nil
    }

    /// Direct calls are user-initiated, so they clear the meditation-pause
    /// marker; the isMeditating sink re-sets it immediately after the
    /// pauseGuide() call it makes itself.
    func pauseGuide() {
        scheduler?.pause()
        isPaused = true
        wasPausedByMeditation = false
    }

    func resumeGuide() {
        scheduler?.resume()
        isPaused = false
        wasPausedByMeditation = false
    }

    func replayLastPrompt() {
        player.replayLast()
    }

    func bindWalkState(
        statusPublisher: AnyPublisher<WalkBuilder.Status, Never>,
        startDatePublisher: AnyPublisher<Date?, Never>,
        isRecordingVoicePublisher: AnyPublisher<Bool, Never>,
        isMeditatingPublisher: AnyPublisher<Bool, Never>
    ) {
        statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.lastKnownWalkStatus = status
                self?.scheduler?.updateStatus(status)
            }
            .store(in: &walkStateBindings)

        startDatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.lastKnownWalkStartDate = date
                self?.scheduler?.updateWalkStartDate(date)
            }
            .store(in: &walkStateBindings)

        isRecordingVoicePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.player.stop() }
                self?.scheduler?.updateIsRecordingVoice(recording)
            }
            .store(in: &walkStateBindings)

        isMeditatingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meditating in
                guard let self, self.isActive else { return }
                if meditating {
                    // Only remember a pause this sink itself caused — ending
                    // meditation must not force-resume a guide the user
                    // paused by hand.
                    if !self.isPaused {
                        self.pauseGuide()
                        self.wasPausedByMeditation = true
                    }
                } else if self.wasPausedByMeditation {
                    self.wasPausedByMeditation = false
                    self.scheduler?.setPostMeditationSilence()
                    self.resumeGuide()
                }
                self.scheduler?.updateIsMeditating(meditating)
            }
            .store(in: &walkStateBindings)
    }

    private func playPrompt(_ prompt: VoiceGuidePrompt, packId: String, generation: Int) {
        guard VoiceGuideFileStore.shared.isAvailable(prompt, packId: packId) else {
            print("[VoiceGuide] Prompt \(prompt.id) unavailable — file not downloaded")
            // The scheduler latched isPlaying before asking us to play;
            // skipping without markPlayed would wedge it silent forever
            // (mirrors MeditationGuideManagement's handling).
            scheduler?.markPlayed(prompt.id)
            return
        }
        player.play(prompt: prompt, packId: packId) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.scheduler?.markPlayed(prompt.id)
        }
    }

    // MARK: - History Persistence

    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Audio/voiceguide", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadHistory(for packId: String) -> Set<String> {
        guard let data = try? Data(contentsOf: historyFileURL),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data),
              let ids = dict[packId] else {
            return []
        }
        return Set(ids)
    }

    private func persistHistory(for packId: String, scheduler: VoiceGuideScheduler) {
        var dict: [String: [String]] = [:]
        if let data = try? Data(contentsOf: historyFileURL),
           let existing = try? JSONDecoder().decode([String: [String]].self, from: data) {
            dict = existing
        }
        dict[packId] = Array(scheduler.playedPromptIds)

        let knownPacks = Set(VoiceGuideManifestService.shared.packs.map(\.id))
        if !knownPacks.isEmpty {
            dict = dict.filter { knownPacks.contains($0.key) }
        }

        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: historyFileURL)
        }
    }

    #if DEBUG
    func _test_tick() { scheduler?.testTick() }
    var _test_playedPromptIds: Set<String> { scheduler?.playedPromptIds ?? [] }
    #endif
}
