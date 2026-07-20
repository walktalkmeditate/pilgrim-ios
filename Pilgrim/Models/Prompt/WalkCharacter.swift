import Foundation

/// Distills what made this walk distinct — length, hour, moon, stillness —
/// into one preamble sentence, so two different walks never open with
/// identical prose. Ordinary walks yield nil; absence of remark is part of
/// the voice.
enum WalkCharacter {

    static func note(context: ActivityContext) -> String? {
        var body: String?
        if context.duration >= 3600 {
            body = "a long walk — the kind where thought thins out and something quieter takes over"
        } else if context.duration < 900 {
            body = "a brief walk, taken anyway — brevity is not smallness"
        }

        var timePhrase: String?
        let hour = Calendar.current.component(.hour, from: context.startDate)
        if hour >= 20 || hour < 5 {
            timePhrase = "into the night"
        } else if hour < 9 {
            timePhrase = "begun before the day claimed its shape"
        }

        var tail: [String] = []
        if context.lunarPhase.illumination >= 0.97 {
            tail.append("under a full moon")
        } else if context.lunarPhase.illumination <= 0.03 {
            tail.append("under a new moon")
        }
        if !context.meditations.isEmpty {
            tail.append("with stillness folded into it")
        }

        guard body != nil || timePhrase != nil || !tail.isEmpty else { return nil }

        var sentence = "This was \(body ?? "a walk")"
        if let timePhrase {
            sentence += " \(timePhrase)"
        }
        if !tail.isEmpty {
            sentence += ", \(tail.joined(separator: ", "))"
        }
        return sentence + "."
    }
}

/// The one shared preamble custom styles build on. Living here — not
/// hardcoded inside CustomPromptStyle — means preamble improvements reach
/// user-authored styles automatically.
enum StandardPreamble {

    static func text(hasSpeech: Bool) -> String {
        hasSpeech
            ? "These are voice recordings captured during a walk, transcribed as spoken. They represent unfiltered thoughts, observations, and feelings that surfaced while moving."
            : "This walk was taken in silence — no words were spoken, only movement. The walker chose presence over expression, letting the body speak through pace, pauses, and the places it was drawn to."
    }
}
