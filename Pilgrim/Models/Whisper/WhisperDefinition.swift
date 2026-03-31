import UIKit

struct WhisperDefinition: Codable, Identifiable {

    let id: String
    let title: String
    let category: WhisperCategory
    let audioFileName: String
    let durationSec: Double
}

enum WhisperCategory: String, Codable, CaseIterable {
    case courage
    case gratitude
    case stillness
    case wonder
    case compassion
    case presence

    var borderColor: UIColor {
        switch self {
        case .courage: return UIColor(red: 0.85, green: 0.65, blue: 0.35, alpha: 1.0)
        case .gratitude: return UIColor(red: 0.80, green: 0.72, blue: 0.45, alpha: 1.0)
        case .stillness: return UIColor(red: 0.55, green: 0.62, blue: 0.68, alpha: 1.0)
        case .wonder: return UIColor(red: 0.65, green: 0.55, blue: 0.75, alpha: 1.0)
        case .compassion: return UIColor(red: 0.50, green: 0.62, blue: 0.45, alpha: 1.0)
        case .presence: return UIColor(red: 0.55, green: 0.45, blue: 0.34, alpha: 1.0)
        }
    }
}
