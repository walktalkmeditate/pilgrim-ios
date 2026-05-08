import SwiftUI

/// Adds the ConstellationOverlay (stars + nebulae + cosmic gradient) on top
/// of any view tree, conditional on the active appearance mode.
///
/// Why a modifier: SwiftUI's `.fullScreenCover` and `.sheet` create separate
/// presentation hierarchies that don't inherit the root ZStack overlay
/// from `PilgrimApp`. Apply this modifier inside cover/sheet content so
/// stars render there too.
struct ConstellationDecor: ViewModifier {
    let includesNebulae: Bool

    @EnvironmentObject private var appearanceManager: AppearanceManager

    func body(content: Content) -> some View {
        content.overlay {
            if appearanceManager.isConstellation {
                ConstellationOverlay(includesNebulae: includesNebulae)
            }
        }
    }
}

extension View {
    /// Adds the constellation overlay (stars + cosmic gradient + optional nebulae).
    /// Pass `nebulae: false` for screens with dense / opaque content (e.g. the
    /// active-walk Mapbox map and the post-walk summary) where the soft purple
    /// nebula clouds clash with the foreground rather than feeling cosmic.
    func constellationDecorated(nebulae: Bool = true) -> some View {
        modifier(ConstellationDecor(includesNebulae: nebulae))
    }
}
