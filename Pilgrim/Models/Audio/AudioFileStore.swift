import Foundation

final class AudioFileStore {

    static let shared = AudioFileStore()

    private let fileManager = FileManager.default
    private let baseDirectory: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Audio", isDirectory: true)
    }

    func localURL(for asset: AudioAsset) -> URL? {
        let url = fileURL(for: asset)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func isAvailable(_ asset: AudioAsset) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: asset).path)
    }

    func destinationURL(for asset: AudioAsset) -> URL {
        let dir = baseDirectory.appendingPathComponent(asset.type.rawValue, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(asset.id).aac")
    }

    func totalDiskUsage() -> Int {
        guard let enumerator = fileManager.enumerator(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }

    func clearAll() {
        try? fileManager.removeItem(at: baseDirectory)
    }

    func availableAssets(from manifest: AudioManifest) -> [AudioAsset] {
        manifest.assets.filter { isAvailable($0) }
    }

    private func fileURL(for asset: AudioAsset) -> URL {
        baseDirectory
            .appendingPathComponent(asset.type.rawValue, isDirectory: true)
            .appendingPathComponent("\(asset.id).aac")
    }
}
