import Foundation

enum WalkMode: String, CaseIterable {
    case wander, together, seek

    var subtitle: String {
        switch self {
        case .wander: return "walk · talk · meditate"
        case .together: return "walk with others nearby"
        case .seek: return "follow the unknown"
        }
    }

    var buttonLabel: String {
        switch self {
        case .wander: return "Wander"
        case .together: return "Walk Together"
        case .seek: return "Seek"
        }
    }

    var isAvailable: Bool {
        self == .wander
    }

    var quotes: [String] {
        switch self {
        case .wander: return (1...6).map { LS["Welcome.Quote.\($0)"] }
        case .together: return (1...3).map { LS["Together.Quote.\($0)"] }
        case .seek: return (1...3).map { LS["Seek.Quote.\($0)"] }
        }
    }
}
