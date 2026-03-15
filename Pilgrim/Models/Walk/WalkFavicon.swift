import Foundation

enum WalkFavicon: String, CaseIterable {
    case flame, leaf, star

    var icon: String {
        switch self {
        case .flame: return "flame.fill"
        case .leaf: return "leaf.fill"
        case .star: return "star.fill"
        }
    }

    var label: String {
        switch self {
        case .flame: return "Transformative"
        case .leaf: return "Peaceful"
        case .star: return "Extraordinary"
        }
    }
}
