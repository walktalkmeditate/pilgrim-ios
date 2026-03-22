import AVFoundation

final class VoiceGuidePlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = VoiceGuidePlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private let fileStore = VoiceGuideFileStore.shared

    private var preDuckVolume: Float?
    private var onFinished: (() -> Void)?
    private var lastPromptId: String?
    private var lastPackId: String?

    var isPlaying: Bool { player?.isPlaying ?? false }
    var hasLastPrompt: Bool { lastPromptId != nil }

    private override init() { super.init() }

    func play(prompt: VoiceGuidePrompt, packId: String, onFinished: (() -> Void)? = nil) {
        guard let url = fileStore.localURL(for: prompt, packId: packId) else { return }

        stop()

        self.onFinished = onFinished
        lastPromptId = prompt.id
        lastPackId = packId

        let currentVolume = soundscapePlayer.currentTargetVolume
        preDuckVolume = currentVolume
        let duckLevel = Float(UserPreferences.voiceGuideDuckLevel.value)
        soundscapePlayer.setVolume(duckLevel, animated: true)

        coordinator.activate(for: .playbackOnly, consumer: "voiceguide")

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = Float(UserPreferences.voiceGuideVolume.value)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("[VoiceGuidePlayer] Playback error: \(error)")
            restoreAndDeactivate()
            self.onFinished = nil
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        onFinished = nil
        restoreAndDeactivate()
    }

    func replayLast() {
        guard let promptId = lastPromptId,
              let packId = lastPackId,
              let pack = VoiceGuideManifestService.shared.pack(byId: packId) else { return }
        let allPrompts = pack.prompts + (pack.meditationPrompts ?? [])
        guard let prompt = allPrompts.first(where: { $0.id == promptId }) else { return }
        play(prompt: prompt, packId: packId)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.restoreAndDeactivate()
            let callback = self?.onFinished
            self?.onFinished = nil
            callback?()
        }
    }

    private func restoreAndDeactivate() {
        if let volume = preDuckVolume {
            soundscapePlayer.setVolume(volume, animated: true)
            preDuckVolume = nil
        }
        coordinator.deactivate(consumer: "voiceguide")
    }
}
