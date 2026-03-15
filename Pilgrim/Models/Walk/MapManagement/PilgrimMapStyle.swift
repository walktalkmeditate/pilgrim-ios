import UIKit
import MapboxMaps

enum PilgrimMapStyle {

    enum Mode {
        case light
        case dark
    }

    static func applyWabiSabiStyle(to map: MapboxMap, mode: Mode) {
        let palette = mode == .dark ? darkPalette : lightPalette
        applyPalette(palette, to: map)
        removeChromeAndPOI(from: map)
        softenBuildings(map, mode: mode)
        softenLanduse(map, mode: mode)
        addHillshade(to: map, mode: mode)
        addAtmosphere(to: map, mode: mode)
    }

    // MARK: - Palettes

    private struct Palette {
        let background: UIColor
        let roads: UIColor
        let roadCases: UIColor
        let water: UIColor
        let labels: UIColor
    }

    private static var lightPalette: Palette {
        Palette(
            background: SeasonalColorEngine.seasonalColor(named: "parchment", intensity: .minimal),
            roads: SeasonalColorEngine.seasonalColor(named: "stone", intensity: .moderate),
            roadCases: SeasonalColorEngine.seasonalColor(named: "fog", intensity: .minimal),
            water: SeasonalColorEngine.seasonalColor(named: "fog", intensity: .minimal),
            labels: SeasonalColorEngine.seasonalColor(named: "fog", intensity: .moderate)
        )
    }

    private static var darkPalette: Palette {
        Palette(
            background: UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1),
            roads: SeasonalColorEngine.seasonalColor(named: "stone", intensity: .moderate)
                .withAlphaComponent(0.5),
            roadCases: UIColor(red: 0.15, green: 0.13, blue: 0.12, alpha: 1),
            water: UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1),
            labels: SeasonalColorEngine.seasonalColor(named: "fog", intensity: .minimal)
                .withAlphaComponent(0.6)
        )
    }

    // MARK: - Apply Palette

    private static func applyPalette(_ palette: Palette, to map: MapboxMap) {
        setColor(map, layer: "background", property: "background-color", color: palette.background)

        let roadFills = [
            "road-motorway-trunk", "road-primary", "road-secondary-tertiary",
            "road-street", "road-minor", "road-construction"
        ]
        for layerId in roadFills {
            setColor(map, layer: layerId, property: "line-color", color: palette.roads)
        }

        let roadCases = [
            "road-motorway-trunk-case", "road-primary-case",
            "road-secondary-tertiary-case", "road-street-case", "road-minor-case"
        ]
        for layerId in roadCases {
            setColor(map, layer: layerId, property: "line-color", color: palette.roadCases)
        }

        let waterLayers = ["water", "water-shadow"]
        for layerId in waterLayers {
            setColor(map, layer: layerId, property: "fill-color", color: palette.water)
        }

        let majorLabels = ["road-label"]
        for layerId in majorLabels {
            setColor(map, layer: layerId, property: "text-color", color: palette.labels)
        }

        let minorLabels = [
            "road-number-shield", "road-exit-shield",
            "path-pedestrian-label", "waterway-label",
            "settlement-minor-label", "settlement-major-label"
        ]
        for layerId in minorLabels {
            try? map.removeLayer(withId: layerId)
        }
    }

    // MARK: - Buildings

    private static func softenBuildings(_ map: MapboxMap, mode: Mode) {
        let buildingLayers = ["building", "building-outline"]
        for layerId in buildingLayers {
            guard map.layerExists(withId: layerId) else { continue }
            let color: UIColor = mode == .dark
                ? UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1)
                : SeasonalColorEngine.seasonalColor(named: "parchment", intensity: .minimal)
                    .blended(with: SeasonalColorEngine.seasonalColor(named: "stone", intensity: .minimal), ratio: 0.15)
            setColor(map, layer: layerId, property: "fill-color", color: color)
            try? map.setLayerProperty(for: layerId, property: "fill-opacity", value: 0.4)
        }
    }

    // MARK: - Land Use (parks, green areas)

    private static func softenLanduse(_ map: MapboxMap, mode: Mode) {
        guard map.layerExists(withId: "landuse") else { return }
        let tint: UIColor = mode == .dark
            ? UIColor(red: 0.11, green: 0.12, blue: 0.10, alpha: 1)
            : SeasonalColorEngine.seasonalColor(named: "moss", intensity: .minimal)
                .withAlphaComponent(0.12)
        setColor(map, layer: "landuse", property: "fill-color", color: tint)
        try? map.setLayerProperty(for: "landuse", property: "fill-opacity", value: 0.5)
    }

    // MARK: - Hillshade

    private static func addHillshade(to map: MapboxMap, mode: Mode) {
        guard !map.sourceExists(withId: "pilgrim-terrain") else { return }

        do {
            var source = RasterDemSource(id: "pilgrim-terrain")
            source.url = "mapbox://mapbox.mapbox-terrain-dem-v1"
            source.tileSize = 514
            try map.addSource(source)

            var hillshade = HillshadeLayer(id: "pilgrim-hillshade", source: "pilgrim-terrain")
            hillshade.hillshadeExaggeration = .constant(0.3)
            if mode == .dark {
                hillshade.hillshadeShadowColor = .constant(StyleColor(UIColor.black.withAlphaComponent(0.4)))
                hillshade.hillshadeHighlightColor = .constant(StyleColor(UIColor.white.withAlphaComponent(0.03)))
            } else {
                hillshade.hillshadeShadowColor = .constant(StyleColor(UIColor.black.withAlphaComponent(0.08)))
                hillshade.hillshadeHighlightColor = .constant(StyleColor(UIColor.white.withAlphaComponent(0.3)))
            }
            try map.addLayer(hillshade, layerPosition: .below("road-minor"))
        } catch {
            print("[PilgrimMapStyle] Hillshade setup failed: \(error)")
        }
    }

    // MARK: - Atmosphere

    private static func addAtmosphere(to map: MapboxMap, mode: Mode) {
        if mode == .dark {
            let atmosphere = Atmosphere()
            try? map.setAtmosphere(atmosphere)
        }
    }

    // MARK: - Remove Chrome

    private static func removeChromeAndPOI(from map: MapboxMap) {
        let removeLayers = [
            "poi-label", "transit-label", "airport-label",
            "settlement-subdivision-label", "natural-point-label",
            "natural-line-label", "state-label", "country-label"
        ]
        for layerId in removeLayers {
            try? map.removeLayer(withId: layerId)
        }
    }

    // MARK: - Helpers

    private static func setColor(_ map: MapboxMap, layer: String, property: String, color: UIColor) {
        guard map.layerExists(withId: layer) else { return }
        try? map.setLayerProperty(for: layer, property: property, value: StyleColor(color).rawValue)
    }
}

private extension UIColor {
    func blended(with other: UIColor, ratio: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * ratio,
            green: g1 + (g2 - g1) * ratio,
            blue: b1 + (b2 - b1) * ratio,
            alpha: a1 + (a2 - a1) * ratio
        )
    }
}
