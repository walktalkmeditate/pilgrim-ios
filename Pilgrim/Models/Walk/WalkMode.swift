import Foundation

enum WalkMode: String, CaseIterable {
    case wander, honor, seek

    var subtitle: String {
        switch self {
        case .wander: return "walk · talk · meditate"
        case .honor: return "walk in their steps"
        case .seek: return "follow the unknown"
        }
    }

    var buttonLabel: String {
        switch self {
        case .wander: return "Wander"
        case .honor: return "Choose a way"
        case .seek: return "Seek"
        }
    }

    var isAvailable: Bool { true }

    var quotes: [String] {
        switch self {
        case .wander: return (1...6).map { LS["Welcome.Quote.\($0)"] }
        case .honor: return (1...3).map { LS["Honor.Quote.\($0)"] }
        case .seek: return (1...3).map { LS["Seek.Quote.\($0)"] }
        }
    }
}
