import SwiftUI

struct LanternShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Base pedestal
        path.addRect(CGRect(x: w * 0.3, y: h * 0.88, width: w * 0.4, height: h * 0.12))

        // Stem
        path.addRect(CGRect(x: w * 0.42, y: h * 0.7, width: w * 0.16, height: h * 0.18))

        // Body (square lantern box)
        path.addRect(CGRect(x: w * 0.22, y: h * 0.35, width: w * 0.56, height: h * 0.35))

        // Window cutout area (lighter fill applied separately)

        // Roof — peaked pyramid
        path.move(to: CGPoint(x: w * 0.12, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.35))
        path.closeSubpath()

        // Finial (top knob)
        path.addEllipse(in: CGRect(x: w * 0.42, y: h * 0.04, width: w * 0.16, height: h * 0.1))

        return path
    }
}

struct LanternWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.addRect(CGRect(x: w * 0.32, y: h * 0.42, width: w * 0.36, height: h * 0.22))

        return path
    }
}
