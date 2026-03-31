import Foundation

enum WhisperCatalog {

    static let all: [WhisperDefinition] = [
        WhisperDefinition(id: "courage-breath", title: "Breathe into your courage", category: .courage, audioFileName: "whisper-courage-breath", durationSec: 8),
        WhisperDefinition(id: "courage-step", title: "Every step is a choice", category: .courage, audioFileName: "whisper-courage-step", durationSec: 7),
        WhisperDefinition(id: "courage-unknown", title: "The unknown is not the enemy", category: .courage, audioFileName: "whisper-courage-unknown", durationSec: 9),

        WhisperDefinition(id: "gratitude-ground", title: "Thank the ground beneath you", category: .gratitude, audioFileName: "whisper-gratitude-ground", durationSec: 8),
        WhisperDefinition(id: "gratitude-air", title: "Grateful for this air", category: .gratitude, audioFileName: "whisper-gratitude-air", durationSec: 7),
        WhisperDefinition(id: "gratitude-body", title: "Your body carries you", category: .gratitude, audioFileName: "whisper-gratitude-body", durationSec: 9),

        WhisperDefinition(id: "stillness-pause", title: "Pause here", category: .stillness, audioFileName: "whisper-stillness-pause", durationSec: 6),
        WhisperDefinition(id: "stillness-listen", title: "Listen to the silence", category: .stillness, audioFileName: "whisper-stillness-listen", durationSec: 8),
        WhisperDefinition(id: "stillness-settle", title: "Let your mind settle", category: .stillness, audioFileName: "whisper-stillness-settle", durationSec: 10),

        WhisperDefinition(id: "wonder-look", title: "Look around you slowly", category: .wonder, audioFileName: "whisper-wonder-look", durationSec: 8),
        WhisperDefinition(id: "wonder-sky", title: "Lift your eyes to the sky", category: .wonder, audioFileName: "whisper-wonder-sky", durationSec: 7),
        WhisperDefinition(id: "wonder-small", title: "Notice something small", category: .wonder, audioFileName: "whisper-wonder-small", durationSec: 8),

        WhisperDefinition(id: "compassion-kind", title: "Be kind to yourself", category: .compassion, audioFileName: "whisper-compassion-kind", durationSec: 7),
        WhisperDefinition(id: "compassion-others", title: "Others walk this path too", category: .compassion, audioFileName: "whisper-compassion-others", durationSec: 9),
        WhisperDefinition(id: "compassion-heart", title: "Open your heart", category: .compassion, audioFileName: "whisper-compassion-heart", durationSec: 8),

        WhisperDefinition(id: "presence-here", title: "You are here, now", category: .presence, audioFileName: "whisper-presence-here", durationSec: 6),
        WhisperDefinition(id: "presence-feet", title: "Feel your feet on the earth", category: .presence, audioFileName: "whisper-presence-feet", durationSec: 8),
        WhisperDefinition(id: "presence-arrive", title: "You have already arrived", category: .presence, audioFileName: "whisper-presence-arrive", durationSec: 9),
    ]

    static func whispers(for category: WhisperCategory) -> [WhisperDefinition] {
        all.filter { $0.category == category }
    }

    static func whisper(byId id: String) -> WhisperDefinition? {
        all.first { $0.id == id }
    }
}
