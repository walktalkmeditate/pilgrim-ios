import AVFoundation
import Foundation

/// Generates short silent audio files so tests can drive real AVAudioPlayer
/// instances without bundling fixtures or touching the network.
enum TestAudioFile {

    /// AVAudioFile infers the container from the file extension (and the
    /// readers trust it), so the content format must match the destination's
    /// name: ".aac"/".m4a" destinations get encoded AAC, everything else
    /// gets PCM WAV. Written to a temp path first, then moved into place.
    @discardableResult
    static func writeSilentAudioFile(to url: URL, duration: TimeInterval = 2.0) throws -> URL {
        let sampleRate = 44_100.0
        let ext = url.pathExtension.lowercased().isEmpty ? "wav" : url.pathExtension.lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext)")

        let settings: [String: Any]
        if ext == "wav" {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                throw NSError(domain: "TestAudioFile", code: 1)
            }
            settings = format.settings
        } else {
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1
            ]
        }

        let file = try AVAudioFile(forWriting: tempURL, settings: settings)
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "TestAudioFile", code: 2)
        }
        buffer.frameLength = frameCount
        try file.write(from: buffer)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
        return url
    }

    static func makePlayer(duration: TimeInterval = 2.0) throws -> AVAudioPlayer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-audio-\(UUID().uuidString).wav")
        try writeSilentAudioFile(to: url, duration: duration)
        return try AVAudioPlayer(contentsOf: url)
    }
}
