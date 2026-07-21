import UIKit

/// A whisper or cairn presence as it renders on the map.
enum MapGlyph {
    case whisper(tint: UIColor)
    case cairn(tier: CairnTier)
}

/// Rasterizes the catalog's vector glyph art into Mapbox-ready
/// `PointAnnotation` images. Mapbox stores raster sprites, so everything
/// is drawn at display scale (R11) and cached — the key space is small
/// and fixed: 8 whisper mood colors and 7 cairn tiers.
///
/// Cache keys deliberately match the formats the annotation managers
/// already use as image names (`whisper-RRGGBB`, `cairn-<tier>`), so the
/// swap from SF Symbols changes pixels, not refresh behavior.
enum MapGlyphImageBuilder {

    private static var cache: [String: UIImage] = [:]

    static func image(for glyph: MapGlyph, size: CGFloat) -> UIImage? {
        let key = "\(cacheKey(for: glyph))-\(Int(size))"
        if let cached = cache[key] {
            return cached
        }
        let rendered: UIImage?
        switch glyph {
        case .whisper(let tint):
            rendered = self.rendered(assetNamed: "whisperWisp", tint: tint, size: size)
        case .cairn(let tier):
            rendered = self.rendered(assetNamed: tier.glyphAssetName, tint: nil, size: size)
        }
        if let rendered {
            cache[key] = rendered
        }
        return rendered
    }

    static func cacheKey(for glyph: MapGlyph) -> String {
        switch glyph {
        case .whisper(let tint):
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            tint.getRed(&red, green: &green, blue: &blue, alpha: nil)
            return String(format: "whisper-%02X%02X%02X",
                          Int(red * 255), Int(green * 255), Int(blue * 255))
        case .cairn(let tier):
            return "cairn-\(tier.rawValue)"
        }
    }

    /// Draws a catalog asset into a square raster at display scale.
    /// `draw(in:)`, not `draw(at:)` — an asset image drawn at `.zero`
    /// rasterizes at its intrinsic size, ignoring the requested one.
    static func rendered(assetNamed name: String, tint: UIColor?, size: CGFloat) -> UIImage? {
        guard var asset = UIImage(named: name) else { return nil }
        if let tint {
            asset = asset.withTintColor(tint, renderingMode: .alwaysOriginal)
        }
        let target = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            asset.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    #if DEBUG
    static func _test_clearCache() {
        cache.removeAll()
    }
    #endif
}
