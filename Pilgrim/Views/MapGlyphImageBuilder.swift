import UIKit

/// A whisper, cairn, or seek clearing presence as it renders on the map.
enum MapGlyph {
    case whisper(tint: UIColor)
    case cairn(tier: CairnTier)
    case seekClearing(tint: UIColor)
}

/// Rasterizes the catalog's vector glyph art into Mapbox-ready
/// `PointAnnotation` images. Mapbox stores raster sprites, so everything
/// is drawn at display scale (R11) and cached — the key space is small
/// and fixed: 8 whisper mood colors, 7 cairn tiers, and the 6 daypart
/// hexes a clearing can be found under.
///
/// Cache keys deliberately match the formats the annotation managers
/// already use as image names (`whisper-RRGGBB`, `cairn-<tier>`), so the
/// swap from SF Symbols changes pixels, not refresh behavior.
enum MapGlyphImageBuilder {

    /// The wisp's one canonical asset name, shared by the map raster path,
    /// the SwiftUI mood rows, and the asset tests.
    static let whisperAssetName = "whisperWisp"

    /// The clearing's tree. A template asset like the wisp — it takes the
    /// hour's light from `SeekSkyLight` rather than carrying its own colour.
    static let seekClearingAssetName = "seekClearing"

    /// Main-thread only, like all callers (buildPoints via updateUIView) —
    /// same discipline as PilgrimMapView.symbolImageCache.
    private static var cache: [String: UIImage] = [:]

    static func image(for glyph: MapGlyph, size: CGFloat) -> UIImage? {
        let key = "\(cacheKey(for: glyph))-\(size)"
        if let cached = cache[key] {
            return cached
        }
        let rendered: UIImage?
        switch glyph {
        case .whisper(let tint):
            rendered = self.rendered(assetNamed: whisperAssetName, tint: tint, size: size)
        case .cairn(let tier):
            rendered = self.rendered(assetNamed: tier.glyphAssetName, tint: nil, size: size)
        case .seekClearing(let tint):
            rendered = self.rendered(assetNamed: seekClearingAssetName, tint: tint, size: size)
        }
        if let rendered {
            cache[key] = rendered
        }
        return rendered
    }

    static func cacheKey(for glyph: MapGlyph) -> String {
        switch glyph {
        case .whisper(let tint):
            return "whisper-\(rgbKey(for: tint))"
        case .cairn(let tier):
            return "cairn-\(tier.rawValue)"
        case .seekClearing(let tint):
            return "clearing-\(rgbKey(for: tint))"
        }
    }

    /// Tints are fixed, opaque literals — `WhisperCategory.borderColor` for
    /// the wisp, `SeekSkyLight.hex` for the clearing. The key hashes RGB
    /// only. A non-RGB-convertible or translucent tint would collide keys —
    /// fail fast in DEBUG.
    private static func rgbKey(for tint: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        let converted = tint.getRed(&red, green: &green, blue: &blue, alpha: nil)
        assert(converted, "glyph tint must be RGB-convertible for a stable cache key")
        return String(format: "%02X%02X%02X",
                      Int(red * 255), Int(green * 255), Int(blue * 255))
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
