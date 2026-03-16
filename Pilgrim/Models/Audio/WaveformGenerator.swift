import AVFoundation

struct WaveformGenerator {

    static func generateSamples(from url: URL, count: Int = 150) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return nil }

        let format = file.processingFormat
        let framesPerBin = max(1, totalFrames / count)
        let chunkSize: AVAudioFrameCount = 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return nil }

        var samples = [Float](repeating: 0, count: count)
        var globalFrame = 0

        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            let toRead = min(chunkSize, remaining)
            do {
                try file.read(into: buffer, frameCount: toRead)
            } catch {
                return nil
            }

            guard let channelData = buffer.floatChannelData?[0] else { return nil }
            let readCount = Int(buffer.frameLength)

            for i in 0..<readCount {
                let bin = min(globalFrame / framesPerBin, count - 1)
                samples[bin] = max(samples[bin], abs(channelData[i]))
                globalFrame += 1
            }
        }

        let peak = samples.max() ?? 1
        if peak > 0 {
            samples = samples.map { $0 / peak }
        }
        return samples
    }
}
