import Foundation

final class VoiceGuideFileStore {

    static let shared = VoiceGuideFileStore()

    private let fileManager = FileManager.default
    private let baseDirectory: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Audio/voiceguide", isDirectory: true)
    }

    func localURL(for prompt: VoiceGuidePrompt, packId: String) -> URL? {
        let url = fileURL(for: prompt, packId: packId)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func isAvailable(_ prompt: VoiceGuidePrompt, packId: String) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: prompt, packId: packId).path)
    }

    func isPackDownloaded(_ pack: VoiceGuidePack) -> Bool {
        pack.prompts.allSatisfy { isAvailable($0, packId: pack.id) }
    }

    func destinationURL(for prompt: VoiceGuidePrompt, packId: String) -> URL {
        let dir = baseDirectory.appendingPathComponent(packId, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(prompt.id).aac")
    }

    func deletePackFiles(_ packId: String) {
        let dir = baseDirectory.appendingPathComponent(packId, isDirectory: true)
        try? fileManager.removeItem(at: dir)
    }

    func packDiskUsage(_ packId: String) -> Int {
        let dir = baseDirectory.appendingPathComponent(packId, isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }

    private func fileURL(for prompt: VoiceGuidePrompt, packId: String) -> URL {
        baseDirectory
            .appendingPathComponent(packId, isDirectory: true)
            .appendingPathComponent("\(prompt.id).aac")
    }
}
