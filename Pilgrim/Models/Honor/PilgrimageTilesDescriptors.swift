// Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift
import CoreLocation
import Foundation

/// The numbers the offline descriptors are built from, kept as plain data
/// so a test can pin them without touching Mapbox.
enum PilgrimageTilesDescriptors {

    /// The SDK downloads whole tile packs in fixed zoom bands — 0–5, 6–10,
    /// 11–14, 15–16 — not the tiles a corridor touches, and caps a store at
    /// 750 unique packs. A range starting at 0 pulls the planet-wide 0–5
    /// pack of every tileset in the style, 206 MB before a single route
    /// tile, and each z6 pack is ~90 MB on top; 11 is the first band whose
    /// packs follow the corridor. The 15–16 band adds building footprints
    /// only and would put the Francés alone at ~1,800 z15-rooted packs, so
    /// Streets ends at 14. Offline, the walk screen's z16 overzooms the
    /// saved z14, and below z11 the whole-route preview draws its line on
    /// bare parchment.
    static let streetsZoom: ClosedRange<Int> = 11...14
    /// The root of the one band the region lives in: a pack is one z11
    /// tile with its descendants to z14, per tileset, so the estimate counts
    /// z11 cells rather than tiles.
    static let packRootZoom = 11
    /// Mixed into every corridor hash. The first field build saved regions
    /// from z0 with the DEM named — 596 MB for the four-stage Nakahechi —
    /// and a region saved under those descriptors must not read as saved:
    /// with the version in the hash it fails the check, the next save
    /// reloads it under the current descriptors, and the store frees the
    /// packs nothing references any more. Bump this whenever the
    /// descriptors change under regions already on phones.
    static let regionVersion = 2
    /// Shikoku and Kumano labels are CJK; rasterizing ideographs on the
    /// device keeps the style pack from carrying every glyph range.
    static let rasterizesIdeographsLocally = true

    /// Distinct XYZ tiles whose centre or any corner lies inside any part of
    /// the corridor, summed over `zooms`. Mapbox unions the parts, so a tile
    /// a quad and its vertex square both cover is downloaded once and counted
    /// once — and the rings of several stages passed together dedup the same
    /// way, which is how a z11 cell two stages share is one pack in the
    /// estimate as it is in the store.
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
