import Foundation

protocol PromptVoice {
    func preamble(hasSpeech: Bool) -> String
    func instruction(hasSpeech: Bool) -> String
}
