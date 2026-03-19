import Foundation

protocol PromptVoice {
    var title: String { get }
    var icon: String { get }
    var voiceDescription: String { get }
    func preamble(hasSpeech: Bool) -> String
    func instruction(hasSpeech: Bool) -> String
}
