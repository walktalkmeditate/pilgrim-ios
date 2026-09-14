import CoreLocation
import MapboxMaps
import QuartzCore

/// The map telling its screen where the camera actually is. Read-only: the
/// `cameraCenter`/`cameraZoom` bindings drive the camera, so a two-way report
/// through them would loop. Only the throttle state lives on the Coordinator.
extension PilgrimMapView {

    /// Mapbox's `onCameraChanged` fires per rendered frame during a pan or a
    /// pinch, and every report that gets through costs a SwiftUI update — the
    /// throttle in `reportCamera` is the point of this pair. Both tokens are
    /// held on the coordinator and cancelled in `dismantleUIView`.
    static func installCameraReport(on mapView: MBMapView, coordinator: Coordinator) {
        mapView.mapboxMap.onCameraChanged.observe { [weak coordinator, weak mapView] _ in
            guard let coordinator, let mapView else { return }
            reportCamera(on: mapView, coordinator: coordinator, throttled: true)
        }.store(in: &coordinator.cameraReportCancelables)
        // A gesture's last frame can land inside the throttle window and be
        // dropped; idle is the one report that must always get through.
        mapView.mapboxMap.onMapIdle.observe { [weak coordinator, weak mapView] _ in
            guard let coordinator, let mapView else { return }
            reportCamera(on: mapView, coordinator: coordinator, throttled: false)
        }.store(in: &coordinator.cameraReportCancelables)
    }

    /// Four reports a second at most.
    private static var cameraReportMinInterval: CFTimeInterval { 0.25 }

    /// Reports only what a consumer would draw differently: a new integer zoom
    /// level, or a center more than `HonorTuning.markPinRefreshMeters` from the
    /// last one — the distance the only consumer (the stage's service marks)
    /// re-selects on, so a finer report would publish work nobody uses.
    private static func reportCamera(on mapView: MBMapView, coordinator: Coordinator, throttled: Bool) {
        guard let report = coordinator.onCameraChanged else { return }
        let now = CACurrentMediaTime()
        if throttled, now - coordinator.lastCameraReportUptime < cameraReportMinInterval { return }
        let state = mapView.mapboxMap.cameraState
        // `Int(_:)` traps on a NaN, which no clamp catches.
        guard state.zoom.isFinite else { return }
        let level = Int(state.zoom)
        let movedFar = coordinator.lastReportedCenter.map { last in
            CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: state.center.latitude, longitude: state.center.longitude))
                > HonorTuning.markPinRefreshMeters
        } ?? true
        guard level != coordinator.lastReportedZoomLevel || movedFar else { return }
        coordinator.lastCameraReportUptime = now
        coordinator.lastReportedZoomLevel = level
        coordinator.lastReportedCenter = state.center
        report(state.center, state.zoom)
    }

    /// SwiftUI's teardown hook. `AnyCancelable` cancels on deinit too; this is
    /// the path that doesn't wait for the coordinator to be released, so a
    /// dismissed screen stops receiving reports at once.
    static func dismantleUIView(_ mapView: MBMapView, coordinator: Coordinator) {
        coordinator.cameraReportCancelables.forEach { $0.cancel() }
        coordinator.cameraReportCancelables.removeAll()
        coordinator.onCameraChanged = nil
    }
}
