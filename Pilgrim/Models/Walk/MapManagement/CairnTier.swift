import Foundation

enum CairnTier: Int, CaseIterable {
    case faint = 0
    case small = 1
    case medium = 2
    case large = 3
    case great = 4
    case sacred = 5
    case eternal = 6

    /// Asset catalog name for this tier's glyph art in Assets.xcassets/glyphs/.
    /// Not the same string as MapGlyphImageBuilder's cache key ("cairn-<rawValue>"),
    /// which preserves the pre-glyph annotation-name format.
    var glyphAssetName: String {
        switch self {
        case .faint: return "cairn-faint"
        case .small: return "cairn-small"
        case .medium: return "cairn-medium"
        case .large: return "cairn-large"
        case .great: return "cairn-great"
        case .sacred: return "cairn-sacred"
        case .eternal: return "cairn-eternal"
        }
    }

    /// "a faint" … "an eternal" — VoiceOver labels splice this after a verb,
    /// and the milestone tier must not read as "a eternal cairn".
    var displayNameWithArticle: String {
        self == .eternal ? "an \(displayName)" : "a \(displayName)"
    }

    /// Natural-language tier name for user-facing text (VoiceOver labels),
    /// deliberately independent of asset naming.
    var displayName: String {
        switch self {
        case .faint: return "faint"
        case .small: return "small"
        case .medium: return "medium"
        case .large: return "large"
        case .great: return "great"
        case .sacred: return "sacred"
        case .eternal: return "eternal"
        }
    }

    /// The one tier derivation for stone-count-driven feedback (placement
    /// haptic, stone chime). StonePlayer and ActiveWalkView both route
    /// through here so the threshold table cannot silently fork again.
    static func soundTier(forStoneCount count: Int) -> Int {
        from(stoneCount: count).soundTier
    }

    static func from(stoneCount: Int) -> CairnTier {
        switch stoneCount {
        case 108...: return .eternal
        case 77...: return .sacred
        case 42...: return .great
        case 12...: return .large
        case 7...: return .medium
        case 3...: return .small
        default: return .faint
        }
    }

    var circleRadius: Double {
        switch self {
        case .faint: return 5
        case .small: return 7
        case .medium: return 9
        case .large: return 11
        case .great: return 13
        case .sacred: return 15
        case .eternal: return 17
        }
    }

    var opacity: Double {
        switch self {
        case .faint: return 0.3
        case .small: return 0.5
        case .medium: return 0.65
        case .large: return 0.8
        case .great: return 0.85
        case .sacred: return 0.9
        case .eternal: return 1.0
        }
    }

    var glows: Bool { self == .eternal }

    var threshold: Int {
        switch self {
        case .faint: return 0
        case .small: return 3
        case .medium: return 7
        case .large: return 12
        case .great: return 42
        case .sacred: return 77
        case .eternal: return 108
        }
    }

    var nextTier: CairnTier? {
        switch self {
        case .faint: return .small
        case .small: return .medium
        case .medium: return .large
        case .large: return .great
        case .great: return .sacred
        case .sacred: return .eternal
        case .eternal: return nil
        }
    }

    var soundTier: Int {
        switch self {
        case .faint: return 1
        case .small: return 2
        case .medium: return 3
        case .large: return 4
        case .great: return 5
        case .sacred: return 6
        case .eternal: return 7
        }
    }
}
