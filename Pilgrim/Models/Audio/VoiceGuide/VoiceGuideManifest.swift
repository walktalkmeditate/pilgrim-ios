import Foundation

struct VoiceGuideManifest: Codable {
    let version: String
    let packs: [VoiceGuidePack]
}

struct VoiceGuidePack: Codable, Identifiable {
    let id: String
    let version: String
    let name: String
    let tagline: String
    let description: String
    let theme: String
    let iconName: String
    let type: String
    let walkTypes: [String]
    let scheduling: PromptDensity
    let totalDurationSec: Double
    let totalSizeBytes: Int
    let prompts: [VoiceGuidePrompt]
}

struct PromptDensity: Codable {
    let densityMinSec: Int
    let densityMaxSec: Int
    let minSpacingSec: Int
    let initialDelaySec: Int
    let walkEndBufferSec: Int
}

struct VoiceGuidePrompt: Codable, Identifiable {
    let id: String
    let seq: Int
    let durationSec: Double
    let fileSizeBytes: Int
    let r2Key: String
}
