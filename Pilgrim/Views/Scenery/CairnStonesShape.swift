import SwiftUI

/// Three stacked stones — the ink-scroll mark of a seek that found places.
/// Widest at the base, each stone slightly off-axis the way real cairns
/// lean, drawn in a unit rect and scaled by the caller.
struct CairnStonesShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Base stone
        path.addEllipse(in: CGRect(
            x: rect.minX + w * 0.10, y: rect.minY + h * 0.68,
            width: w * 0.80, height: h * 0.30
        ))
        // Middle stone, nudged left
        path.addEllipse(in: CGRect(
            x: rect.minX + w * 0.18, y: rect.minY + h * 0.40,
            width: w * 0.60, height: h * 0.26
        ))
        // Top stone, nudged right
        path.addEllipse(in: CGRect(
            x: rect.minX + w * 0.32, y: rect.minY + h * 0.16,
            width: w * 0.40, height: h * 0.22
        ))
        return path
    }
}
