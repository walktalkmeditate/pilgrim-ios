import Foundation

struct ContemplativeVoice: PromptVoice {
    func preamble(hasSpeech: Bool) -> String {
        hasSpeech
            ? "During a walking meditation, these words arose naturally from the rhythm of movement and breath. They were not planned or curated — they emerged as the body moved through space."
            : "This walk was taken in silence — no words were spoken, only movement. The walker chose presence over expression, letting the body speak through pace, pauses, and the places it was drawn to."
    }

    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Please receive these walking thoughts with gentleness. Help me sit with what emerged, without rushing to analyze or fix. What was my body and spirit trying to tell me through these words? What wants to be noticed, held, or simply acknowledged? Respond in a contemplative, unhurried tone."
            : "Reflect on what this silent walk might reveal. What does its rhythm suggest? Its pauses, its waypoints, its duration? Help the walker see what their body and feet were saying when their voice was still. Respond in a contemplative, unhurried tone."
    }
}

struct ReflectiveVoice: PromptVoice {
    func preamble(hasSpeech: Bool) -> String {
        hasSpeech
            ? "These are voice recordings captured during a walk, transcribed as spoken. They represent unfiltered thoughts, observations, and feelings that surfaced while moving."
            : "A walk taken without words. The walker moved through the world in observation, letting thoughts form and dissolve without voicing them."
    }

    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Please analyze these walking reflections for patterns, recurring themes, and emotional undercurrents. What connections do you see between the different moments? What might I be processing or working through? What contradictions or tensions are present? Offer observations that help me understand myself better."
            : "Read the shape of this walk — its pace, its pauses, its waypoints — as you would read a text. What patterns do you see? What might the walker have been processing? What does the choice of silence itself suggest? Offer observations that help them understand themselves."
    }
}

struct CreativeVoice: PromptVoice {
    func preamble(hasSpeech: Bool) -> String {
        hasSpeech
            ? "A walker spoke these words into the open air while moving through the world. They are raw material — fragments of observation, feeling, and thought gathered by a body in motion."
            : "A silent walk — no spoken words, only footsteps marking time and space. The raw material here is movement itself: the distance covered, the pace kept, the places the walker paused or marked."
    }

    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Transform these walking fragments into something creative. You might compose a poem, write a short prose piece, create a series of haiku, or craft a brief narrative. Let the rhythm of the walk inform the rhythm of the writing. Preserve the essence but elevate the expression."
            : "Transform this silent walk into something creative. Let the rhythm of the steps become the rhythm of the writing. You might compose a poem from the walk's shape, write a meditation on silence and motion, or craft a piece that gives voice to what the walker's feet were saying. Preserve the quietness but give it form."
    }
}

struct GratitudeVoice: PromptVoice {
    func preamble(hasSpeech: Bool) -> String {
        hasSpeech
            ? "These words were spoken during a walk — a time of moving through the world with awareness. Somewhere in these observations and thoughts are seeds of gratitude, even if not explicitly stated."
            : "This walk was taken in silence — a choice to simply be present with the world rather than narrate it."
    }

    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Help me find the gratitude woven through these walking thoughts. What am I thankful for, even if I didn't say it directly? What blessings are hiding in my observations? What can I appreciate about this moment in my life, this body that walks, this world I moved through? Frame your response as a practice of thanksgiving."
            : "Find the gratitude hidden in this silent walk. What is the walker thankful for, even without saying it? The body that carried them, the ground beneath their feet, the places they marked as meaningful, the time they gave themselves. Frame your response as a practice of thanksgiving for the walk itself."
    }
}

struct PhilosophicalVoice: PromptVoice {
    func preamble(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Walking has long been a companion to philosophical thought — from Aristotle's peripatetic school to Kierkegaard's daily constitutionals. These words emerged during such a walk, where movement and thought intertwined."
            : "Walking in silence has a long philosophical tradition — from Zen walking meditation to Kierkegaard's solitary constitutionals. This walk carries that lineage, choosing wordless presence over verbal reflection."
    }

    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Engage with these walking thoughts philosophically. What deeper questions are being asked? What assumptions about life, meaning, or existence are being explored? Connect my observations to broader wisdom traditions, philosophical concepts, or universal human experiences. Help me think more deeply about what I was already beginning to think."
            : "Engage with this silent walk philosophically. What does the act of walking without speaking suggest about the walker's relationship to thought, language, and presence? Connect the walk's physical details — its duration, pace, waypoints — to broader questions about consciousness, embodiment, and meaning."
    }
}

struct JournalingVoice: PromptVoice {
    func preamble(hasSpeech: Bool) -> String {
        hasSpeech
            ? "The following are raw, unedited voice recordings from a walk. They capture thoughts as they occurred — scattered, honest, and in the moment."
            : "The following is a walk taken without voice recordings. No words were spoken — only footsteps, pauses, and marked waypoints tell the story."
    }

    func instruction(hasSpeech: Bool) -> String {
        hasSpeech
            ? "Help me turn these scattered walking thoughts into a coherent journal entry. Organize the themes, add transitions between ideas, and create a narrative flow while preserving my authentic voice. The result should read as a thoughtful, personal journal entry that I could return to and understand. Include a brief summary of the walk's key themes at the end."
            : "Help the walker create a journal entry from this silent walk. Use the walk's metadata — its timing, distance, pace, waypoints, and any meditation sessions — to reconstruct a narrative. What was the walk like? What might the walker have been thinking? Create a reflective entry they could return to, written in second person ('You walked...')."
    }
}

extension PromptStyle {
    var voice: PromptVoice {
        switch self {
        case .contemplative: return ContemplativeVoice()
        case .reflective: return ReflectiveVoice()
        case .creative: return CreativeVoice()
        case .gratitude: return GratitudeVoice()
        case .philosophical: return PhilosophicalVoice()
        case .journaling: return JournalingVoice()
        }
    }
}
