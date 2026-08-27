import Foundation

protocol PromptVoice {
    func preamble(hasSpeech: Bool) -> String
    func instruction(hasSpeech: Bool) -> String
    /// Voice-specific output constraints for the downstream model, rendered
    /// into the prompt's closing "How to respond" contract alongside the
    /// shared lines every style carries.
    func responseConstraints(hasSpeech: Bool) -> [String]
    /// Which context blocks this voice receives. Defaults to `.full`, so
    /// `CustomPromptStyle` and any future voice are unaffected until they
    /// opt out deliberately.
    var contextPolicy: PromptContextPolicy { get }
}

extension PromptVoice {
    func responseConstraints(hasSpeech: Bool) -> [String] { [] }
    var contextPolicy: PromptContextPolicy { .full }
}
