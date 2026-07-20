import Foundation

protocol PromptVoice {
    func preamble(hasSpeech: Bool) -> String
    func instruction(hasSpeech: Bool) -> String
    /// Voice-specific output constraints for the downstream model, rendered
    /// into the prompt's closing "How to respond" contract alongside the
    /// shared lines every style carries.
    func responseConstraints(hasSpeech: Bool) -> [String]
}

extension PromptVoice {
    func responseConstraints(hasSpeech: Bool) -> [String] { [] }
}
