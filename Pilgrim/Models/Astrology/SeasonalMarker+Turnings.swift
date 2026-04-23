import SwiftUI

extension SeasonalMarker {

    /// Single-character kanji representing this turning. Nil for cross-quarter markers.
    var kanji: String? {
        switch self {
        case .springEquinox:  return "春分"
        case .summerSolstice: return "夏至"
        case .autumnEquinox:  return "秋分"
        case .winterSolstice: return "冬至"
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }

    /// Localized banner copy. Solstices read "Today the sun stands still";
    /// equinoxes read "Today, day equals night". Nil for cross-quarter.
    var bannerText: String? {
        switch self {
        case .springEquinox, .autumnEquinox:  return LS.turningEquinoxBanner
        case .summerSolstice, .winterSolstice: return LS.turningSolsticeBanner
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }

    /// Asset Catalog color name for this turning's walking-segment color.
    /// Nil for cross-quarter.
    var colorAssetName: String? {
        switch self {
        case .springEquinox:  return "turningJade"
        case .summerSolstice: return "turningGold"
        case .autumnEquinox:  return "turningClaret"
        case .winterSolstice: return "turningIndigo"
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }

    /// SwiftUI Color resolved from the asset catalog. Nil for cross-quarter.
    var color: Color? {
        guard let name = colorAssetName else { return nil }
        return Color(name)
    }

    /// UIColor resolved from the asset catalog. Nil for cross-quarter.
    var uiColor: UIColor? {
        guard let name = colorAssetName else { return nil }
        return UIColor(named: name)
    }

    /// True iff this marker is one of the 4 main solstices/equinoxes.
    /// False for the 4 cross-quarter markers (imbolc/beltane/lughnasadh/samhain).
    var isTurning: Bool {
        switch self {
        case .springEquinox, .summerSolstice, .autumnEquinox, .winterSolstice: return true
        case .imbolc, .beltane, .lughnasadh, .samhain: return false
        }
    }

    /// `SealColorPalette` entry for the goshuin seal on this turning.
    /// Nil for cross-quarter.
    var sealColor: SealColorPalette.SealColor? {
        switch self {
        case .springEquinox:  return SealColorPalette.turningJade
        case .summerSolstice: return SealColorPalette.turningGold
        case .autumnEquinox:  return SealColorPalette.turningClaret
        case .winterSolstice: return SealColorPalette.turningIndigo
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }
}
