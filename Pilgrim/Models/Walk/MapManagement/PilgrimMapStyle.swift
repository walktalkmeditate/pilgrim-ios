import UIKit
import MapboxMaps

enum PilgrimMapStyle {

    static func applyWabiSabiStyle(to mapboxMap: MapboxMap) {
        let parchment = SeasonalColorEngine.seasonalColor(named: "parchment", intensity: .minimal)
        let stone = SeasonalColorEngine.seasonalColor(named: "stone", intensity: .moderate)
        let fog = SeasonalColorEngine.seasonalColor(named: "fog", intensity: .minimal)

        setLayerColor(mapboxMap, layer: "background", property: "background-color", color: parchment)

        let roadLayers = [
            "road-motorway-trunk", "road-primary", "road-secondary-tertiary",
            "road-street", "road-minor", "road-construction",
            "road-motorway-trunk-case", "road-primary-case",
            "road-secondary-tertiary-case", "road-street-case", "road-minor-case"
        ]
        for layerId in roadLayers {
            setLayerColor(mapboxMap, layer: layerId, property: "line-color", color: stone)
        }

        let waterLayers = ["water", "water-shadow"]
        for layerId in waterLayers {
            setLayerColor(mapboxMap, layer: layerId, property: "fill-color", color: fog)
        }

        let labelLayers = [
            "road-label", "road-number-shield", "road-exit-shield",
            "path-pedestrian-label", "waterway-label"
        ]
        for layerId in labelLayers {
            setLayerColor(mapboxMap, layer: layerId, property: "text-color", color: fog)
        }

        let removeLayers = [
            "poi-label", "transit-label", "airport-label",
            "settlement-subdivision-label", "natural-point-label",
            "natural-line-label"
        ]
        for layerId in removeLayers {
            try? mapboxMap.removeLayer(withId: layerId)
        }
    }

    private static func setLayerColor(_ map: MapboxMap, layer: String, property: String, color: UIColor) {
        guard map.layerExists(withId: layer) else { return }
        try? map.setLayerProperty(for: layer, property: property, value: StyleColor(color).rawValue)
    }
}
