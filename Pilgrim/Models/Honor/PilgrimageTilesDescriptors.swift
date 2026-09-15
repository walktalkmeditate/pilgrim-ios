// Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift
import CoreLocation
import Foundation

/// The numbers the offline descriptors are built from, kept as plain data
/// so a test can pin them without touching Mapbox.
enum PilgrimageTilesDescriptors {

    /// The SDK loads tile packs in fixed zoom bands — 0–5, 6–10, 11–14,
    /// 15–16 — and recommends choosing ceilings on a band edge. z15 costs
    /// the same packs as z16, so the walk screen's z16 is native.
    static let streetsZoom: ClosedRange<Int> = 0...16
    /// The DEM tileset has no z15; 14 is its ceiling and a band edge.
    static let terrainZoom: ClosedRange<Int> = 0...14
    /// Added at runtime by `PilgrimMapStyle.applyWabiSabiStyle`, so not in
    /// either base style: it has to be named or the hillshade is blank offline.
    static let terrainTileset = "mapbox://mapbox.mapbox-terrain-dem-v1"
    /// Shikoku and Kumano labels are CJK; rasterizing ideographs on the
    /// device keeps the style pack from carrying every glyph range.
    static let rasterizesIdeographsLocally = true

    /// Distinct XYZ tiles whose centre or any corner lies inside any part of
    /// the corridor, summed over `zooms`. Mapbox unions the parts, so a tile
    /// a quad and its vertex square both cover is downloaded once and counted
    /// once. Below z10 a corridor touches a handful of tiles, a rounding
    /// error the estimate leaves out.
    static func tileCount(rings: [[CLLocationCoordinate2D]], zooms: ClosedRange<Int>) -> Int {
        let parts = rings.filter { $0.count > 3 }
        guard !parts.isEmpty else { return 0 }
        // A winding stage has hundreds of parts and most tiles in its overall
        // box touch none of them, so each part's own box rejects it before
        // the five containment probes run. Box-disjoint implies untouched —
        // every way `tileTouches` can be true puts a point in both boxes —
        // so this is a rejection, not an approximation.
        let boxes = parts.map { part -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) in
            let lats = part.map(\.latitude), lons = part.map(\.longitude)
            return (lats.min()!, lats.max()!, lons.min()!, lons.max()!)
        }
        var total = 0
        for z in zooms {
            let n = Double(1 << z)
            let (xMin, yMax) = tile(lat: boxes.map(\.minLat).min()!, lon: boxes.map(\.minLon).min()!, n: n)
            let (xMax, yMin) = tile(lat: boxes.map(\.maxLat).max()!, lon: boxes.map(\.maxLon).max()!, n: n)
            // The sweep visits each (z, x, y) once and stops at the first
            // part that touches it, so overlapping parts cannot double-count.
            for x in xMin...xMax {
                for y in yMin...yMax {
                    let southWest = coordinate(x: Double(x), y: Double(y + 1), n: n)
                    let northEast = coordinate(x: Double(x + 1), y: Double(y), n: n)
                    let touched = parts.indices.contains { index in
                        let box = boxes[index]
                        return box.maxLat >= southWest.latitude && box.minLat <= northEast.latitude
                            && box.maxLon >= southWest.longitude && box.minLon <= northEast.longitude
                            && tileTouches(parts[index], x: x, y: y, n: n)
                    }
                    if touched { total += 1 }
                }
            }
        }
        return total
    }

    private static func tile(lat: Double, lon: Double, n: Double) -> (x: Int, y: Int) {
        let x = Int(floor((lon + 180) / 360 * n))
        let latRad = lat * .pi / 180
        let y = Int(floor((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n))
        return (min(max(x, 0), Int(n) - 1), min(max(y, 0), Int(n) - 1))
    }

    private static func coordinate(x: Double, y: Double, n: Double) -> CLLocationCoordinate2D {
        let lon = x / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// A tile counts when any of its corners or its centre is inside the
    /// ring, or when a ring vertex is inside the tile. Cheap and slightly
    /// generous; the estimate errs high rather than low.
    private static func tileTouches(_ ring: [CLLocationCoordinate2D], x: Int, y: Int, n: Double) -> Bool {
        let probes = [
            coordinate(x: Double(x), y: Double(y), n: n),
            coordinate(x: Double(x + 1), y: Double(y), n: n),
            coordinate(x: Double(x), y: Double(y + 1), n: n),
            coordinate(x: Double(x + 1), y: Double(y + 1), n: n),
            coordinate(x: Double(x) + 0.5, y: Double(y) + 0.5, n: n)
        ]
        if probes.contains(where: { WayGeometry.ringContains(ring, $0) }) { return true }
        let west = coordinate(x: Double(x), y: Double(y + 1), n: n), east = coordinate(x: Double(x + 1), y: Double(y), n: n)
        return ring.contains { $0.longitude >= west.longitude && $0.longitude <= east.longitude
            && $0.latitude >= west.latitude && $0.latitude <= east.latitude }
    }
}
