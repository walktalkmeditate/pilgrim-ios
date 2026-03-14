import SwiftUI

public extension Color {

    static var parchment: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "parchment", intensity: .minimal))
    }
    static var parchmentSecondary: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "parchmentSecondary", intensity: .minimal))
    }
    static var parchmentTertiary: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "parchmentTertiary", intensity: .minimal))
    }

    static var stone: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full))
    }
    static var ink: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "ink", intensity: .minimal))
    }
    static var moss: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "moss", intensity: .full))
    }
    static var rust: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "rust", intensity: .full))
    }
    static var fog: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "fog", intensity: .moderate))
    }
    static var dawn: Color {
        Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full))
    }

    static var background: Color { parchment }
    static var secondaryBackground: Color { parchmentSecondary }
    static var tertiaryBackground: Color { parchmentTertiary }
}
