import Foundation

struct AudioAsset: Codable, Identifiable, Equatable {

    enum AssetType: String, Codable {
        case bell
        case soundscape
    }

    enum UsageTag: String, Codable {
        case intro
        case outro
    }

    let id: String
    let type: AssetType
    let name: String
    let displayName: String
    let durationSec: Double
    let r2Key: String
    let fileSizeBytes: Int
    let usageTags: [UsageTag]

    var isIntro: Bool { usageTags.contains(.intro) }
    var isOutro: Bool { usageTags.contains(.outro) }
}

struct AudioManifest: Codable {
    let version: String
    let assets: [AudioAsset]

    var bells: [AudioAsset] { assets.filter { $0.type == .bell } }
    var soundscapes: [AudioAsset] { assets.filter { $0.type == .soundscape } }
}
