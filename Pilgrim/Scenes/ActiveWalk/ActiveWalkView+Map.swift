import CoreLocation
import SwiftUI

/// The walk map itself and the small round audio buttons floating over it.
/// Split out of `ActiveWalkView.swift`, which sits near the `file_length`
/// gate; the members it reads (`mapBottomInset`, `activeTurning`,
/// `handleAnnotationTap`) lost their `private` for this file's sake.
extension ActiveWalkView {

    func mapSection() -> some View {
        let waypointPins = viewModel.waypoints.map { wp in
            PilgrimAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: wp.latitude, longitude: wp.longitude),
                kind: .waypoint(label: wp.label, icon: wp.icon)
            )
        }
        // Proximity and Way pins are both memoized in the view model (AF43) —
        // reading stored properties here keeps body evaluations free of
        // distance math and of a per-frame `WayGeometry` build.
        return PilgrimMapView(
            showsUserLocation: true,
            // A Way card's header can send the camera to its moment; the map
            // follows the walker again the moment that focus clears.
            followsUserLocation: viewModel.honorFocus == nil,
            routeSegments: viewModel.routeSegments,
            pinAnnotations: waypointPins + viewModel.proximityPins + viewModel.honorMarkPins + viewModel.honorPins,
            onAnnotationTap: { annotation in
                handleAnnotationTap(annotation)
            },
            seekFog: viewModel.seekFogState,
            seekPulse: viewModel.seekPulse,
            cameraCenter: .constant(viewModel.honorFocus),
            cameraZoom: .constant(PilgrimMapView.followPuckZoom),
            bottomInset: mapBottomInset,
            initialCamera: viewModel.mapCameraSeed,
            fadesInOnStyleLoad: true,
            walkingColor: activeTurning?.uiColor ?? .moss,
            isMeditating: $viewModel.isMeditating,
            honorWay: viewModel.honorWayState,
            companion: viewModel.companionCoordinate,
            onCameraChanged: { center, zoom in
                viewModel.mapCameraDidChange(center: center, zoom: zoom)
            }
        )
    }

    func audioIndicator(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.ink)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        // Fixed .black, not adaptive .ink: .ink inverts to
                        // near-white in dark mode and renders as a light halo
                        // under each button on the dark map. Matches the fixed
                        // shadow on the stats sheet background above.
                        .fill(Color.parchmentSecondary)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )
        }
    }

    func handleAnnotationTap(_ annotation: PilgrimAnnotation) {
        switch annotation.kind {
        case .whisper:
            let coord = annotation.coordinate
            if let cached = GeoCacheService.shared.cachedWhispers.first(where: {
                abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
            }),
               let category = cached.resolvedCategory,
               let definition = WhisperManifestService.shared.placeableWhispers(for: category).randomElement() {
                WhisperPlayer.shared.play(definition)
                HapticPattern.whisperProximity.fire()
            }
        case .cairn:
            let coord = annotation.coordinate
            if let cached = GeoCacheService.shared.cachedCairns.first(where: {
                abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
            }) {
                tappedCairn = cached
            }
        default:
            showWayCard(for: annotation)
        }
    }
}
