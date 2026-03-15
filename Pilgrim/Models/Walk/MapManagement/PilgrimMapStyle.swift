import UIKit
import MapboxMaps

enum PilgrimMapStyle {

    static func applyWabiSabiStyle(to mapboxMap: MapboxMap) {
        setLayerColor(mapboxMap, layer: "background", property: "background-color", hex: "#F5F0E8")

        let roadLayers = [
            "road-motorway-trunk", "road-primary", "road-secondary-tertiary",
            "road-street", "road-minor", "road-construction",
            "road-motorway-trunk-case", "road-primary-case",
            "road-secondary-tertiary-case", "road-street-case", "road-minor-case"
        ]
        for layerId in roadLayers {
            setLayerColor(mapboxMap, layer: layerId, property: "line-color", hex: "#8B7355")
        }

        let waterLayers = ["water", "water-shadow"]
        for layerId in waterLayers {
            setLayerColor(mapboxMap, layer: layerId, property: "fill-color", hex: "#D5CFC7")
        }

        let labelLayers = [
            "road-label", "road-number-shield", "road-exit-shield",
            "path-pedestrian-label", "waterway-label"
        ]
        for layerId in labelLayers {
            setLayerColor(mapboxMap, layer: layerId, property: "text-color", hex: "#B8AFA2")
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

    private static func setLayerColor(_ map: MapboxMap, layer: String, property: String, hex: String) {
        guard map.layerExists(withId: layer) else { return }
        let color = StyleColor(UIColor(hex: hex))
        try? map.setLayerProperty(for: layer, property: property, value: color.rawValue)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
