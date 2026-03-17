import Foundation
import Combine

final class SoundManagement: ObservableObject {

    private let bellPlayer = BellPlayer.shared
    private let soundscapePlayer = SoundscapePlayer.shared
    private let manifestService = AudioManifestService.shared
    private let fileStore = AudioFileStore.shared
    private var pendingSoundscapeStart: DispatchWorkItem?
    private var pendingEndBell: DispatchWorkItem?

    @Published private(set) var isSoundscapePlaying = false
    private var soundscapeCancellable: AnyCancellable?

    init() {
        soundscapeCancellable = soundscapePlayer.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: \.isSoundscapePlaying, on: self)
    }

    func toggleSoundscape() {
        if soundscapePlayer.isPlaying {
            stopSoundscape()
        } else {
            startSoundscape()
        }
    }

    private var isSoundsEnabled: Bool {
        UserPreferences.soundsEnabled.value
    }

    private var hapticEnabled: Bool {
        UserPreferences.bellHapticEnabled.value
    }

    private func playBell(id: String?) {
        guard isSoundsEnabled,
              let bellId = id,
              let asset = manifestService.asset(byId: bellId),
              fileStore.isAvailable(asset) else { return }
        bellPlayer.play(asset, volume: Float(UserPreferences.bellVolume.value), withHaptic: hapticEnabled)
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

    func onWalkStart() {
        playBell(id: UserPreferences.walkStartBellId.value)
    }

    func onWalkEnd() {
        cancelPending()
        stopSoundscape()
        playBell(id: UserPreferences.walkEndBellId.value)
    }

    func onMeditationStart() {
        cancelPending()
        playBell(id: UserPreferences.meditationStartBellId.value)
        let bellDuration = bellPlayer.currentDuration
        let delay = max(0.5, bellDuration)
        let work = DispatchWorkItem { [weak self] in
            self?.startSoundscape()
        }
        pendingSoundscapeStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func onMeditationEnd() {
        cancelPending()
        stopSoundscape()
        let work = DispatchWorkItem { [weak self] in
            self?.playBell(id: UserPreferences.meditationEndBellId.value)
        }
        pendingEndBell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func cancelPending() {
        pendingSoundscapeStart?.cancel()
        pendingSoundscapeStart = nil
        pendingEndBell?.cancel()
        pendingEndBell = nil
    }
}
