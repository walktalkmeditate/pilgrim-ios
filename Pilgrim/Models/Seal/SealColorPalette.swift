import UIKit

enum SealColorPalette {

    struct SealColor: Hashable {
        let light: UIColor
        let dark: UIColor
        let cssVar: String
    }

    // Warm (Transformative / flame)
    static let rust      = SealColor(light: UIColor(hex: "#A0634B"), dark: UIColor(hex: "#C47E63"), cssVar: "--seal-rust")
    static let ember     = SealColor(light: UIColor(hex: "#B5553A"), dark: UIColor(hex: "#D4735A"), cssVar: "--seal-ember")
    static let sienna    = SealColor(light: UIColor(hex: "#946B4E"), dark: UIColor(hex: "#B88A6A"), cssVar: "--seal-sienna")
    static let copper    = SealColor(light: UIColor(hex: "#B87333"), dark: UIColor(hex: "#D4955E"), cssVar: "--seal-copper")

    // Cool (Peaceful / leaf)
    static let moss      = SealColor(light: UIColor(hex: "#7A8B6F"), dark: UIColor(hex: "#95A895"), cssVar: "--seal-moss")
    static let sage      = SealColor(light: UIColor(hex: "#8A9A7B"), dark: UIColor(hex: "#A3B396"), cssVar: "--seal-sage")
    static let seaGlass  = SealColor(light: UIColor(hex: "#6B8E8E"), dark: UIColor(hex: "#89ABAB"), cssVar: "--seal-seaglass")
    static let mist      = SealColor(light: UIColor(hex: "#8FA3A3"), dark: UIColor(hex: "#A8B8B8"), cssVar: "--seal-mist")

    // Accent (Extraordinary / star)
    static let indigo    = SealColor(light: UIColor(hex: "#4B5A78"), dark: UIColor(hex: "#6E7F9E"), cssVar: "--seal-indigo")
    static let gold      = SealColor(light: UIColor(hex: "#B8973E"), dark: UIColor(hex: "#D4B35E"), cssVar: "--seal-gold")
    static let twilight  = SealColor(light: UIColor(hex: "#6B5B7B"), dark: UIColor(hex: "#8E7E9E"), cssVar: "--seal-twilight")
    static let amethyst  = SealColor(light: UIColor(hex: "#7B6B8B"), dark: UIColor(hex: "#9E8EAE"), cssVar: "--seal-amethyst")

    // Neutral (Unmarked)
    static let stone     = SealColor(light: UIColor(hex: "#8B7355"), dark: UIColor(hex: "#B8976E"), cssVar: "--stone")
    static let dawn      = SealColor(light: UIColor(hex: "#C4956A"), dark: UIColor(hex: "#D4A87A"), cssVar: "--dawn")
    static let fog       = SealColor(light: UIColor(hex: "#B8AFA2"), dark: UIColor(hex: "#6B6359"), cssVar: "--fog")

    static let warmColors    = [rust, ember, sienna, copper]
    static let coolColors    = [moss, sage, seaGlass, mist]
    static let accentColors  = [indigo, gold, twilight, amethyst]
    static let neutralColors = [stone, dawn, fog]

    static func color(for favicon: WalkFavicon?, hashByte: UInt8) -> SealColor {
        switch favicon {
        case .flame:
            return warmColors[Int(hashByte) % warmColors.count]
        case .leaf:
            return coolColors[Int(hashByte) % coolColors.count]
        case .star:
            return accentColors[Int(hashByte) % accentColors.count]
        case nil:
            return neutralColors[Int(hashByte) % neutralColors.count]
        }
    }

    static func uiColor(for favicon: WalkFavicon?, hashByte: UInt8) -> UIColor {
        let sealColor = color(for: favicon, hashByte: hashByte)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? sealColor.dark : sealColor.light
        }
    }
}
