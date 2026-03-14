import SwiftUI

struct StoneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.15, y: h * 0.7))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.85, y: h * 0.7),
            control: CGPoint(x: w * 0.5, y: 0)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.15, y: h * 0.7),
            control: CGPoint(x: w * 0.5, y: h)
        )
        path.closeSubpath()

        return path
    }
}
