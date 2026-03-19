import SwiftUI

enum AppearanceMode: String {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var resolvedScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
