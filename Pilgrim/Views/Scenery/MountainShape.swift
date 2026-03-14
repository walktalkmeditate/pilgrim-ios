import SwiftUI

struct MountainShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.15))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.3))
        path.addLine(to: CGPoint(x: w * 0.7, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        path.move(to: CGPoint(x: w * 0.6, y: h * 0.15))
        path.addLine(to: CGPoint(x: w * 0.7, y: 0))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.15))
        path.closeSubpath()

        return path
    }
}
