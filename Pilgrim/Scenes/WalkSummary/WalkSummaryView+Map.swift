import SwiftUI
import CoreLocation

// MARK: - Map section + reliquary annotation glue
//
// Extracted from `WalkSummaryView.swift` to keep the main type body under
// SwiftLint's `type_body_length` limit. The functionality is logically a
// continuation of the walk summary's view body, just split into a separate
// extension for line-budget reasons.

extension WalkSummaryView {

    /// Tap handler for map pin annotations. Photo pins route to the carousel by setting
    /// `activePhotoID` (which scrolls the carousel via its `scrollPosition` binding) — the
    /// preview sheet is intentionally NOT opened here, per the plan's rule that map pin
    /// taps focus the carousel rather than preview.
    func handleAnnotationTap(_ annotation: PilgrimAnnotation) {
        if case .photo(let localIdentifier) = annotation.kind {
            withAnimation(.easeInOut(duration: 0.2)) {
                activePhotoID = localIdentifier
            }
        }
    }

    /// Combines the always-shown route-derived annotations with photo pins from the
    /// reliquary, gated by both the user preference toggle and the live Photos permission
    /// state. When either gate is closed, returns just the base annotations so the map
    /// looks exactly as it does on `main`.
    var combinedAnnotations: [PilgrimAnnotation] {
        guard UserPreferences.walkReliquaryEnabled.value,
              PermissionManager.standard.isPhotosGranted else {
            return cachedAnnotations
        }
        let photoPins = photoCandidates
            .filter { $0.isPinned }
            .map { candidate in
                PilgrimAnnotation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: candidate.capturedLat,
                        longitude: candidate.capturedLng
                    ),
                    kind: .photo(localIdentifier: candidate.localIdentifier)
                )
            }
        return cachedAnnotations + photoPins
    }

    private var walkTurning: SeasonalMarker? {
        let hemisphereRaw = UserPreferences.hemisphereOverride.value
        let hemisphere = hemisphereRaw.flatMap { Hemisphere(rawValue: $0) } ?? .northern
        let coord = hemisphere == .southern
            ? CLLocationCoordinate2D(latitude: -1, longitude: 0)
            : CLLocationCoordinate2D(latitude: 1, longitude: 0)
        return TurningDayService.turning(for: walk.startDate, at: coord)
    }

    @ViewBuilder
    var mapSection: some View {
        Group {
            if !routeCoordinates.isEmpty {
                PilgrimMapView(
                    isInteractive: revealPhase == .revealed,
                    showsUserLocation: false,
                    routeSegments: cachedSegments,
                    pinAnnotations: combinedAnnotations,
                    onAnnotationTap: handleAnnotationTap,
                    activePhotoID: activePhotoID,
                    cameraCenter: $cameraCenter,
                    cameraZoom: $cameraZoom,
                    cameraBounds: cameraBounds,
                    cameraDuration: cameraDuration,
                    walkingColor: walkTurning?.uiColor ?? .moss
                )
                .frame(height: 320)
                .mask(
                    RadialGradient(
                        gradient: Gradient(colors: [.white, .white, .white.opacity(0)]),
                        center: .center,
                        startRadius: 80,
                        endRadius: 180
                    )
                )
                .padding(.horizontal, -Constants.UI.Padding.normal)
            } else {
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.big)
                    .fill(Color.parchmentSecondary)
                    .frame(height: 280)
                    .overlay(
                        Text("No route data")
                            .font(Constants.Typography.body)
                            .foregroundColor(.fog)
                    )
            }
        }
    }
}
