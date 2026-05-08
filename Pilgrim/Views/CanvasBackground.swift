import SwiftUI

struct CanvasBackground: ViewModifier {
    @EnvironmentObject private var appearanceManager: AppearanceManager

    func body(content: Content) -> some View {
        content.background(
            appearanceManager.isConstellation
                ? Color(red: 0.039, green: 0.039, blue: 0.071)
                : Color.parchment
        )
    }
}

extension View {
    /// Top-level screen background. Paints parchment normally, deep indigo
    /// in Constellation mode. Reactive via injected AppearanceManager.
    func canvasBackground() -> some View {
        modifier(CanvasBackground())
    }
}
