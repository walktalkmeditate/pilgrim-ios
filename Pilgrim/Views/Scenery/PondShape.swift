import SwiftUI

struct PondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.addEllipse(in: CGRect(x: w * 0.1, y: h * 0.25, width: w * 0.8, height: h * 0.5))

        path.move(to: CGPoint(x: w * 0.35, y: h * 0.42))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.65, y: h * 0.42),
            control: CGPoint(x: w * 0.5, y: h * 0.35)
        )

        return path
    }
}
