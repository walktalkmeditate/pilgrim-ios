import SwiftUI

enum AppearanceMode: String {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case constellation = "constellation"

    var resolvedScheme: ColorScheme? {
        switch self {
        case .system:        return nil
        case .light:         return .light
        case .dark:          return .dark
        case .constellation: return .dark
        }
    }

    var isConstellation: Bool {
        self == .constellation
    }
}
