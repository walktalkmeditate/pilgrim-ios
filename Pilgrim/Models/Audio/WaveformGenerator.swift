import AVFoundation

struct WaveformGenerator {

    static func generateSamples(from url: URL, count: Int = 150) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }

        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let totalFrames = Int(buffer.frameLength)
        let samplesPerBin = max(1, totalFrames / count)
        var samples: [Float] = []
        samples.reserveCapacity(count)

        for bin in 0..<count {
            let start = bin * samplesPerBin
            let end = min(start + samplesPerBin, totalFrames)
            guard start < totalFrames else {
                samples.append(0)
                continue
            }
            var maxAmp: Float = 0
            for i in start..<end {
                maxAmp = max(maxAmp, abs(channelData[i]))
            }
            samples.append(maxAmp)
        }

        let peak = samples.max() ?? 1
        if peak > 0 {
            samples = samples.map { $0 / peak }
        }
        return samples
    }
}
