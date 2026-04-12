import UIKit

struct WhisperDefinition: Codable, Identifiable {

    let id: String
    let title: String
    let category: WhisperCategory
    let audioFileName: String
    let durationSec: Double
    let retiredAt: Date?
}

enum WhisperCategory: String, Codable, CaseIterable {
    case presence
    case lightness
    case wonder
    case gratitude
    case compassion
    case courage
    case stillness
    case play

    var borderColor: UIColor {
        switch self {
        case .presence: return UIColor(red: 0.11, green: 0.23, blue: 0.29, alpha: 1.0)
        case .lightness: return UIColor(red: 0.76, green: 0.65, blue: 0.55, alpha: 1.0)
        case .wonder: return UIColor(red: 0.66, green: 0.72, blue: 0.75, alpha: 1.0)
        case .gratitude: return UIColor(red: 0.78, green: 0.63, blue: 0.31, alpha: 1.0)
        case .compassion: return UIColor(red: 0.66, green: 0.85, blue: 0.82, alpha: 1.0)
        case .courage: return UIColor(red: 0.78, green: 0.72, blue: 0.53, alpha: 1.0)
        case .stillness: return UIColor(red: 0.72, green: 0.58, blue: 0.42, alpha: 1.0)
        case .play: return UIColor(red: 0.75, green: 0.40, blue: 0.22, alpha: 1.0)
        }
    }
}
