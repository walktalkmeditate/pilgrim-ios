import SwiftUI

struct ToriiGateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let pillarW = w * 0.09

        let leftX = w * 0.18
        let rightX = w * 0.82 - pillarW

        // Left pillar — tapers slightly outward at base
        path.move(to: CGPoint(x: leftX, y: h * 0.22))
        path.addLine(to: CGPoint(x: leftX - w * 0.02, y: h))
        path.addLine(to: CGPoint(x: leftX + pillarW + w * 0.02, y: h))
        path.addLine(to: CGPoint(x: leftX + pillarW, y: h * 0.22))
        path.closeSubpath()

        // Right pillar
        path.move(to: CGPoint(x: rightX, y: h * 0.22))
        path.addLine(to: CGPoint(x: rightX - w * 0.02, y: h))
        path.addLine(to: CGPoint(x: rightX + pillarW + w * 0.02, y: h))
        path.addLine(to: CGPoint(x: rightX + pillarW, y: h * 0.22))
        path.closeSubpath()

        // Kasagi (top beam) — curved, extends past pillars
        let beamH = h * 0.07
        let overhang = w * 0.08
        path.move(to: CGPoint(x: -overhang, y: h * 0.12 + beamH))
        path.addQuadCurve(
            to: CGPoint(x: w + overhang, y: h * 0.12 + beamH),
            control: CGPoint(x: w * 0.5, y: h * 0.04)
        )
        path.addLine(to: CGPoint(x: w + overhang, y: h * 0.12 + beamH * 2))
        path.addQuadCurve(
            to: CGPoint(x: -overhang, y: h * 0.12 + beamH * 2),
            control: CGPoint(x: w * 0.5, y: h * 0.12 + beamH)
        )
        path.closeSubpath()

        // Nuki (crossbeam) connecting pillars
        let nY = h * 0.3
        path.addRect(CGRect(x: leftX, y: nY, width: rightX + pillarW - leftX, height: h * 0.04))

        return path
    }
}
