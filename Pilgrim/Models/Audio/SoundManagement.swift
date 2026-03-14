import Foundation
import Combine

final class SoundManagement {

    private let bellPlayer = BellPlayer.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private let manifestService = AudioManifestService.shared
    private let fileStore = AudioFileStore.shared

    private var isSoundsEnabled: Bool {
        UserPreferences.soundsEnabled.value
    }

    func playStartBell() {
        guard isSoundsEnabled else { return }
        guard let bellId = UserPreferences.selectedStartBellId.value,
              let asset = manifestService.asset(byId: bellId),
              fileStore.isAvailable(asset) else { return }
        bellPlayer.play(asset, volume: Float(UserPreferences.bellVolume.value))
    }

    func playEndBell() {
        guard isSoundsEnabled else { return }
        guard let bellId = UserPreferences.selectedEndBellId.value,
              let asset = manifestService.asset(byId: bellId),
              fileStore.isAvailable(asset) else { return }
        bellPlayer.play(asset, volume: Float(UserPreferences.bellVolume.value))
    }

    func startSoundscape() {
        guard isSoundsEnabled else { return }
        guard let scapeId = UserPreferences.selectedSoundscapeId.value,
              let asset = manifestService.asset(byId: scapeId),
              fileStore.isAvailable(asset) else { return }
        soundscapePlayer.play(asset, volume: Float(UserPreferences.soundscapeVolume.value))
    }

    func stopSoundscape() {
        soundscapePlayer.stop()
    }

    func onMeditationStart() {
        playStartBell()
        let bellDuration = bellPlayer.currentDuration
        let delay = max(0.5, bellDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startSoundscape()
        }
    }

    func onMeditationEnd() {
        stopSoundscape()
        let delay: TimeInterval = 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.playEndBell()
        }
    }

    func onWalkStart() {
        playStartBell()
    }

    func onWalkEnd() {
        stopSoundscape()
        playEndBell()
    }
}
