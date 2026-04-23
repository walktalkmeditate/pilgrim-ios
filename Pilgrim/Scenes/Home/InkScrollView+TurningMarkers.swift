import SwiftUI
import CoreLocation

extension InkScrollView {

    /// Renders an inline kanji glyph at the position of each turning-day
    /// walk in the user's history. A permanent visual marker — users who
    /// walk many turnings see them accumulate across their scroll.
    ///
    /// Hemisphere classification uses the user's current hemisphere
    /// (from `UserPreferences.hemisphereOverride`) rather than per-walk
    /// coordinates, because `WalkSnapshot` doesn't carry coordinates.
    /// Users who move hemispheres will see their old walks reclassified.
    func turningMarkers(positions: [CalligraphyPathRenderer.DotPosition]) -> some View {
        let markers = computeTurningMarkers(positions: positions)
        return ForEach(markers, id: \.id) { marker in
            Text(marker.kanji)
                .font(Constants.Typography.caption)
                .foregroundColor(marker.color.opacity(0.55))
                .position(x: marker.x, y: marker.y - 14)
                .accessibilityHidden(true)
        }
    }

    struct TurningMarker: Identifiable {
        let id: UUID
        let x: CGFloat
        let y: CGFloat
        let kanji: String
        let color: Color
    }

    private func computeTurningMarkers(positions: [CalligraphyPathRenderer.DotPosition]) -> [TurningMarker] {
        guard positions.count == snapshots.count else { return [] }
        let hemisphereRawValue = UserPreferences.hemisphereOverride.value
        let latitude: Double
        if let raw = hemisphereRawValue, let hemisphere = Hemisphere(rawValue: raw) {
            latitude = hemisphere == .southern ? -1 : 1
        } else {
            latitude = 1
        }
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: 0)

        var markers: [TurningMarker] = []
        for (snapshot, position) in zip(snapshots, positions) {
            guard let turning = TurningDayService.turning(for: snapshot.startDate, at: coord),
                  let kanji = turning.kanji,
                  let color = turning.color else {
                continue
            }
            markers.append(TurningMarker(
                id: snapshot.id,
                x: position.center.x,
                y: position.center.y,
                kanji: kanji,
                color: color
            ))
        }
        return markers
    }
}
