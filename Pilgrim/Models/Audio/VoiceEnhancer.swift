import AVFoundation
import AudioToolbox

final class VoiceEnhancer {

    static let shared = VoiceEnhancer()
    private let processingQueue = DispatchQueue(label: "VoiceEnhancer", qos: .utility)

    private init() {}

    func enhance(_ fileURL: URL, completion: @escaping (Bool) -> Void) {
        processingQueue.async {
            let success = self.processFile(at: fileURL)
            DispatchQueue.main.async { completion(success) }
        }
    }

    func waitForPendingWork() async {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                continuation.resume()
            }
        }
    }

    private func processFile(at fileURL: URL) -> Bool {
        let tempURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let inputFile = try AVAudioFile(forReading: fileURL)
            let format = inputFile.processingFormat
            let frameCount = AVAudioFrameCount(inputFile.length)
            guard frameCount > 0 else { return false }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            let eq = AVAudioUnitEQ(numberOfBands: 5)
            configureEQ(eq)

            let compressorDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let compressor = AVAudioUnitEffect(audioComponentDescription: compressorDesc)

            let limiterDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_PeakLimiter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)

            let reverb = AVAudioUnitReverb()
            configureReverb(reverb)

            engine.attach(player)
            engine.attach(eq)
            engine.attach(compressor)
            engine.attach(limiter)
            engine.attach(reverb)

            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: compressor, format: format)
            engine.connect(compressor, to: limiter, format: format)
            engine.connect(limiter, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)

            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()

            configureCompressor(compressor)
            configureLimiter(limiter)

            player.scheduleFile(inputFile, at: nil)
            player.play()

            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let outputFile = try AVAudioFile(
                forWriting: tempURL,
                settings: outputSettings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: engine.manualRenderingMaximumFrameCount
            ) else {
                throw NSError(domain: "VoiceEnhancer", code: -2)
            }

            while engine.manualRenderingSampleTime < Int64(frameCount) {
                let framesToRender = min(
                    buffer.frameCapacity,
                    AVAudioFrameCount(Int64(frameCount) - engine.manualRenderingSampleTime)
                )
                let status = try engine.renderOffline(framesToRender, to: buffer)
                switch status {
                case .success:
                    try outputFile.write(from: buffer)
                case .insufficientDataFromInputNode:
                    break
                case .cannotDoInCurrentContext, .error:
                    throw NSError(domain: "VoiceEnhancer", code: -1)
                @unknown default:
                    break
                }
            }

            engine.stop()

            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            return true
        } catch {
            print("[VoiceEnhancer] Enhancement failed: \(error)")
            return false
        }
    }

    private func configureEQ(_ eq: AVAudioUnitEQ) {
        let bands = eq.bands

        bands[0].filterType = .highPass
        bands[0].frequency = 80
        bands[0].bypass = false

        bands[1].filterType = .lowShelf
        bands[1].frequency = 250
        bands[1].gain = 2.5
        bands[1].bypass = false

        bands[2].filterType = .parametric
        bands[2].frequency = 3800
        bands[2].bandwidth = 1.0
        bands[2].gain = 4.0
        bands[2].bypass = false

        bands[3].filterType = .parametric
        bands[3].frequency = 6500
        bands[3].bandwidth = 0.8
        bands[3].gain = -3.0
        bands[3].bypass = false

        bands[4].filterType = .highShelf
        bands[4].frequency = 11000
        bands[4].gain = -4.0
        bands[4].bypass = false
    }

    // DynamicsProcessor params: 0=threshold, 1=headRoom, 4=attackTime, 5=releaseTime, 6=masterGain
    private func configureCompressor(_ effect: AVAudioUnitEffect) {
        let au = effect.audioUnit
        AudioUnitSetParameter(au, 0, kAudioUnitScope_Global, 0, -20, 0)
        AudioUnitSetParameter(au, 1, kAudioUnitScope_Global, 0, 5, 0)
        AudioUnitSetParameter(au, 4, kAudioUnitScope_Global, 0, 0.005, 0)
        AudioUnitSetParameter(au, 5, kAudioUnitScope_Global, 0, 0.1, 0)
        AudioUnitSetParameter(au, 6, kAudioUnitScope_Global, 0, 6, 0)
    }

    // PeakLimiter params: 0=attackTime, 1=decayTime, 2=preGain
    private func configureLimiter(_ effect: AVAudioUnitEffect) {
        let au = effect.audioUnit
        AudioUnitSetParameter(au, 0, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(au, 1, kAudioUnitScope_Global, 0, 0.05, 0)
        AudioUnitSetParameter(au, 2, kAudioUnitScope_Global, 0, 0, 0)
    }

    private func configureReverb(_ reverb: AVAudioUnitReverb) {
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 8
    }
}
