import UIKit

extension UIColor {

    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    static let accentColor = UIColor(named: "accentColor") ?? .systemBrown
    static let stone = UIColor(named: "stone") ?? .systemBrown
    static let ink = UIColor(named: "ink") ?? .label
    static let parchment = UIColor(named: "parchment") ?? .systemBackground
    static let parchmentSecondary = UIColor(named: "parchmentSecondary") ?? .secondarySystemBackground
    static let parchmentTertiary = UIColor(named: "parchmentTertiary") ?? .tertiarySystemBackground
    static let moss = UIColor(named: "moss") ?? .systemGreen
    static let rust = UIColor(named: "rust") ?? .systemRed
    static let fog = UIColor(named: "fog") ?? .secondaryLabel
    static let dawn = UIColor(named: "dawn") ?? .systemOrange
}
