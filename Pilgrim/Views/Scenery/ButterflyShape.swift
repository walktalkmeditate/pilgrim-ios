import SwiftUI

struct ButterflyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w * 0.5

        // Body
        path.addEllipse(in: CGRect(x: cx - w * 0.04, y: h * 0.3, width: w * 0.08, height: h * 0.45))

        // Left wing (upper)
        path.addEllipse(in: CGRect(x: w * 0.02, y: h * 0.15, width: w * 0.42, height: h * 0.4))

        // Left wing (lower)
        path.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.5, width: w * 0.34, height: h * 0.3))

        // Right wing (upper)
        path.addEllipse(in: CGRect(x: w * 0.56, y: h * 0.15, width: w * 0.42, height: h * 0.4))

        // Right wing (lower)
        path.addEllipse(in: CGRect(x: w * 0.58, y: h * 0.5, width: w * 0.34, height: h * 0.3))

        // Antennae
        path.move(to: CGPoint(x: cx - w * 0.02, y: h * 0.3))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.25, y: h * 0.05),
            control: CGPoint(x: w * 0.3, y: h * 0.15)
        )

        path.move(to: CGPoint(x: cx + w * 0.02, y: h * 0.3))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.75, y: h * 0.05),
            control: CGPoint(x: w * 0.7, y: h * 0.15)
        )

        return path
    }
}
