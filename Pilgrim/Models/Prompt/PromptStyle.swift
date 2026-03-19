import Foundation

enum PromptStyle: String, CaseIterable, Identifiable {
    case contemplative
    case reflective
    case creative
    case gratitude
    case philosophical
    case journaling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contemplative: return "Contemplative"
        case .reflective: return "Reflective"
        case .creative: return "Creative"
        case .gratitude: return "Gratitude"
        case .philosophical: return "Philosophical"
        case .journaling: return "Journaling"
        }
    }

    var icon: String {
        switch self {
        case .contemplative: return "leaf.fill"
        case .reflective: return "eye.fill"
        case .creative: return "paintbrush.fill"
        case .gratitude: return "heart.fill"
        case .philosophical: return "books.vertical.fill"
        case .journaling: return "pencil.and.scribble"
        }
    }

    var description: String {
        switch self {
        case .contemplative: return "Sit with what emerged from movement"
        case .reflective: return "Identify patterns and emotional undercurrents"
        case .creative: return "Transform thoughts into poetry or metaphor"
        case .gratitude: return "Find thanksgiving in observations"
        case .philosophical: return "Explore deeper meaning and wisdom"
        case .journaling: return "Structure raw thoughts into a journal entry"
        }
    }
}
