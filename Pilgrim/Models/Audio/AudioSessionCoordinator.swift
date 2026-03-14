import AVFoundation

final class AudioSessionCoordinator {

    static let shared = AudioSessionCoordinator()

    enum Mode {
        case idle
        case playbackOnly
        case recordingOnly
        case recordAndPlay
    }

    private(set) var currentMode: Mode = .idle
    private var activeConsumers: Set<String> = []
    private let queue = DispatchQueue(label: "AudioSessionCoordinator")

    private init() {}

    func activate(for mode: Mode, consumer: String) {
        queue.sync {
            activeConsumers.insert(consumer)
            applyMode(mode)
        }
    }

    func deactivate(consumer: String) {
        queue.sync {
            activeConsumers.remove(consumer)
            if activeConsumers.isEmpty {
                applyMode(.idle)
            }
        }
    }

    func requestMode(playback: Bool, recording: Bool) -> Mode {
        if playback && recording { return .recordAndPlay }
        if playback { return .playbackOnly }
        if recording { return .recordingOnly }
        return .idle
    }

    private func applyMode(_ mode: Mode) {
        currentMode = mode
        let session = AVAudioSession.sharedInstance()

        do {
            switch mode {
            case .idle:
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            case .playbackOnly:
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            case .recordingOnly:
                try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
            case .recordAndPlay:
                try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                try session.setActive(true)
            }
        } catch {
            print("[AudioSessionCoordinator] Failed to apply mode \(mode): \(error)")
        }
    }
}
