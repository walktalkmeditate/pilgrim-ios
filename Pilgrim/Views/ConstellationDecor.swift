import SwiftUI

/// Adds the ConstellationOverlay (stars + nebulae + cosmic gradient) on top
/// of any view tree, conditional on the active appearance mode.
///
/// Why a modifier: SwiftUI's `.fullScreenCover` and `.sheet` create separate
/// presentation hierarchies that don't inherit the root ZStack overlay
/// from `PilgrimApp`. Apply this modifier inside cover/sheet content so
/// stars render there too.
struct ConstellationDecor: ViewModifier {
    @EnvironmentObject private var appearanceManager: AppearanceManager

    func body(content: Content) -> some View {
        content.overlay {
            if appearanceManager.isConstellation {
                ConstellationOverlay()
            }
        }
    }
}

extension View {
    func constellationDecorated() -> some View {
        modifier(ConstellationDecor())
    }
}
