import SwiftUI

struct TreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.55))
        path.closeSubpath()

        path.move(to: CGPoint(x: w * 0.5, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.75))
        path.closeSubpath()

        path.addRect(CGRect(x: w * 0.42, y: h * 0.75, width: w * 0.16, height: h * 0.25))

        return path
    }
}
