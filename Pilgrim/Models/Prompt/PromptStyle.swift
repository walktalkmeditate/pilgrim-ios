import Foundation

enum PromptStyle: String, CaseIterable, Identifiable {
    case contemplative
    case reflective
    case creative
    case gratitude
    case philosophical
    case journaling
    case oblique

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contemplative: return "Contemplative"
        case .reflective: return "Reflective"
        case .creative: return "Creative"
        case .gratitude: return "Gratitude"
        case .philosophical: return "Philosophical"
        case .journaling: return "Journaling"
        case .oblique: return "Oblique"
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
        case .oblique: return "circle.dotted"
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
        case .oblique: return "What has not moved"
        }
    }
}

extension PromptStyle {

    /// Oblique is gated on whether the `Unchanged:` block actually exists
    /// for this walk, not on a walk-count threshold — `unchangedBlock` is
    /// already nil whenever the current walk is silent, history is thin,
    /// `UserPreferences.threadsAfterWalks` is off, or history is deep but
    /// nothing has held still yet (every signal requires at least
    /// `DossierSensesInvariance.minimumInvariantWalks` qualifying walks
    /// before it may fire). Checking the block directly is the only gate
    /// that can't tell `ObliqueVoice` to read a block that isn't in the
    /// prompt. Every other style is always available.
    func isAvailable(unchangedBlockPresent: Bool) -> Bool {
        guard self == .oblique else { return true }
        return unchangedBlockPresent
    }

    /// Shown dimmed in the picker while unavailable. True for every case
    /// that fails the gate above — thin history, a silent walk, or a
    /// history-deep walk where nothing has held still yet — so one string
    /// covers all of them without lying. It reads as the voice needing to
    /// hear more, not as a level to grind.
    var waitingCopy: String? {
        self == .oblique ? "Still listening. A few more walks with your voice." : nil
    }
}
