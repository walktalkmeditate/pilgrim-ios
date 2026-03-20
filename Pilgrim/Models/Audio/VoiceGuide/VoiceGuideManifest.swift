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
    let meditationScheduling: PromptDensity?
    let meditationPrompts: [VoiceGuidePrompt]?

    var hasMeditationGuide: Bool {
        !(meditationPrompts ?? []).isEmpty
    }
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
    let phase: String?

    init(id: String, seq: Int, durationSec: Double, fileSizeBytes: Int, r2Key: String, phase: String? = nil) {
        self.id = id
        self.seq = seq
        self.durationSec = durationSec
        self.fileSizeBytes = fileSizeBytes
        self.r2Key = r2Key
        self.phase = phase
    }
}

enum PromptPhase: String {
    case settling
    case deepening
    case closing
}
