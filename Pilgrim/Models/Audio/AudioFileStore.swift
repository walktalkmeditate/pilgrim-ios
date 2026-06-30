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

    // The base Audio/ directory is shared: voice-guide packs, their
    // manifest, and prompt history live under it too (Audio/voiceguide/,
    // Audio/manifest.json). This store only owns the per-AssetType
    // subdirectories (Audio/bell/, Audio/soundscape/) — disk usage and
    // clearing must never touch the rest.
    private var ownedDirectories: [URL] {
        [AudioAsset.AssetType.bell, .soundscape].map {
            baseDirectory.appendingPathComponent($0.rawValue, isDirectory: true)
        }
    }

    func totalDiskUsage() -> Int {
        var total = 0
        for directory in ownedDirectories {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
                continue
            }
            for case let url as URL in enumerator {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                total += size
            }
        }
        return total
    }

    func clearAll() {
        for directory in ownedDirectories {
            try? fileManager.removeItem(at: directory)
        }
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
