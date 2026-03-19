import Foundation
import Combine

final class MeditationGuideManagement: ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var isVoicePlaying = false

    private var scheduler: VoiceGuideScheduler?
    private let player = VoiceGuidePlayer.shared
    private var generation = 0
    private var currentPackId: String?

    func startGuiding(pack: VoiceGuidePack) {
        stopGuiding()

        guard let medPrompts = pack.meditationPrompts,
              let medScheduling = pack.meditationScheduling,
              !medPrompts.isEmpty else { return }

        generation += 1
        let capturedGeneration = generation
        currentPackId = pack.id

        player.stop()

        let sched = VoiceGuideScheduler(
            prompts: medPrompts,
            scheduling: medScheduling,
            context: .meditation,
            startDate: Date(),
            settlingThresholdSec: 5 * 60,
            closingThresholdSec: 15 * 60
        )
        sched.onShouldPlay = { [weak self] prompt in
            self?.playPrompt(prompt, packId: pack.id, generation: capturedGeneration)
        }
        scheduler = sched
        isActive = true

        sched.start()
    }

    func pauseGuide() {
        scheduler?.pause()
        if isVoicePlaying {
            player.stop()
            isVoicePlaying = false
        }
    }

    func resumeGuide() {
        scheduler?.resume()
    }

    func stopGuiding() {
        scheduler?.stop()
        player.stop()
        scheduler = nil
        isActive = false
        isVoicePlaying = false
        currentPackId = nil
    }

    private func playPrompt(_ prompt: VoiceGuidePrompt, packId: String, generation: Int) {
        guard VoiceGuideFileStore.shared.isAvailable(prompt, packId: packId) else {
            scheduler?.markPlayed(prompt.id)
            return
        }
        isVoicePlaying = true
        player.play(prompt: prompt, packId: packId) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.isVoicePlaying = false
            self.scheduler?.markPlayed(prompt.id)
        }
    }
}
