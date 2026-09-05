import CoreLocation
import Foundation

/// Which of a stage's service marks the walk map carries: chosen from the
/// walker's place and the camera's zoom, and re-chosen only when one of those
/// has moved enough to change the answer. Split out of
/// `ActiveWalkViewModel+Honor.swift`, which sits near SwiftLint's file length.
extension ActiveWalkViewModel {

    /// The nearest-forty selection follows the walker, but a resort of every
    /// mark on the stage is not a per-fix job — 200 m at a time.
    func bindMarkPins() {
        markPinAnchor = nil
        honorLocationFixes
            .sink { [weak self] location in
                self?.refreshMarkPinsIfWalkerMoved(to: location.coordinate)
            }
            .store(in: &honorCancellables)
    }

    func refreshMarkPinsIfWalkerMoved(to coordinate: CLLocationCoordinate2D) {
        if let anchor = markPinAnchor {
            let moved = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard moved >= HonorTuning.markPinRefreshMeters else { return }
        }
        markPinAnchor = coordinate
        applyMarkPins()
    }

    /// The walk map starts out following the puck, but the walker can pinch
    /// away from that zoom — and the marks are hidden below
    /// `WayMarkPins.drawFromZoom`, so a pinch alone can change what is drawn
    /// while the walker stands still.
    func mapCameraDidChange(center: CLLocationCoordinate2D, zoom: CGFloat) {
        mapCameraCenter = center
        // `Int(_:)` traps on a NaN, which no clamp catches.
        guard zoom.isFinite else { return }
        let wasLevel = Int(mapCameraZoom)
        mapCameraZoom = zoom
        guard Int(zoom) != wasLevel else { return }
        applyMarkPins()
    }

    /// Published only on a real change: this array reaches the map's own diff,
    /// and an equal one republished re-runs the walk's body for nothing.
    /// Before the first fix the camera's center stands in for the walker —
    /// it is where they are looking, and the map seeds it from their last
    /// known place.
    private func applyMarkPins() {
        guard let marks = way?.marks, !marks.isEmpty else {
            if !honorMarkPins.isEmpty { honorMarkPins = [] }
            return
        }
        let pins = WayMarkPins.pins(marks: marks, zoom: mapCameraZoom, near: markPinAnchor ?? mapCameraCenter)
        if pins != honorMarkPins { honorMarkPins = pins }
    }
}
