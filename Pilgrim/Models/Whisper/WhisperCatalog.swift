import Foundation

enum WhisperCatalog {

    static let all: [WhisperDefinition] = [
        WhisperDefinition(id: "presence-1", title: "What do you see right now?", category: .presence, audioFileName: "whisper-presence-1", durationSec: 6),
        WhisperDefinition(id: "presence-2", title: "Feel your feet on the earth", category: .presence, audioFileName: "whisper-presence-2", durationSec: 8),
        WhisperDefinition(id: "presence-3", title: "You are here", category: .presence, audioFileName: "whisper-presence-3", durationSec: 5),

        WhisperDefinition(id: "lightness-1", title: "You are doing great", category: .lightness, audioFileName: "whisper-lightness-1", durationSec: 6),
        WhisperDefinition(id: "lightness-2", title: "Whatever you were worrying about can wait", category: .lightness, audioFileName: "whisper-lightness-2", durationSec: 8),
        WhisperDefinition(id: "lightness-3", title: "Take a breath", category: .lightness, audioFileName: "whisper-lightness-3", durationSec: 8),

        WhisperDefinition(id: "wonder-1", title: "Something extraordinary is happening", category: .wonder, audioFileName: "whisper-wonder-1", durationSec: 7),
        WhisperDefinition(id: "wonder-2", title: "The light left its source long ago", category: .wonder, audioFileName: "whisper-wonder-2", durationSec: 7),
        WhisperDefinition(id: "wonder-3", title: "You are spinning through space", category: .wonder, audioFileName: "whisper-wonder-3", durationSec: 9),

        WhisperDefinition(id: "gratitude-1", title: "Thank the one who planted this tree", category: .gratitude, audioFileName: "whisper-gratitude-1", durationSec: 8),
        WhisperDefinition(id: "gratitude-2", title: "Your body carried you here", category: .gratitude, audioFileName: "whisper-gratitude-2", durationSec: 8),
        WhisperDefinition(id: "gratitude-3", title: "This moment is a gift", category: .gratitude, audioFileName: "whisper-gratitude-3", durationSec: 6),

        WhisperDefinition(id: "compassion-1", title: "Others have walked here with heavy hearts", category: .compassion, audioFileName: "whisper-compassion-1", durationSec: 6),
        WhisperDefinition(id: "compassion-2", title: "Set something down", category: .compassion, audioFileName: "whisper-compassion-2", durationSec: 6),
        WhisperDefinition(id: "compassion-3", title: "The path does not ask you to be perfect", category: .compassion, audioFileName: "whisper-compassion-3", durationSec: 8),

        WhisperDefinition(id: "courage-1", title: "The next step is the only one that matters", category: .courage, audioFileName: "whisper-courage-1", durationSec: 6),
        WhisperDefinition(id: "courage-2", title: "What you seek is also seeking you", category: .courage, audioFileName: "whisper-courage-2", durationSec: 6),
        WhisperDefinition(id: "courage-3", title: "You already know the answer", category: .courage, audioFileName: "whisper-courage-3", durationSec: 7),

        WhisperDefinition(id: "stillness-1", title: "Be still", category: .stillness, audioFileName: "whisper-stillness-1", durationSec: 3),
        WhisperDefinition(id: "stillness-2", title: "Breathe", category: .stillness, audioFileName: "whisper-stillness-2", durationSec: 4),
        WhisperDefinition(id: "stillness-3", title: "You are an animal on the earth", category: .stillness, audioFileName: "whisper-stillness-3", durationSec: 6)
    ]

    static func whispers(for category: WhisperCategory) -> [WhisperDefinition] {
        all.filter { $0.category == category }
    }

    static func whisper(byId id: String) -> WhisperDefinition? {
        all.first { $0.id == id }
    }
}
