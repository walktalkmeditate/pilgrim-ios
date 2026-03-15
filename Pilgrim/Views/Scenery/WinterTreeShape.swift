import SwiftUI

struct WinterTreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w * 0.5

        let trunkBottom = h
        let trunkTop = h * 0.35
        let trunkWidthBottom = w * 0.06
        let trunkWidthTop = w * 0.03

        path.move(to: CGPoint(x: cx - trunkWidthBottom, y: trunkBottom))
        path.addLine(to: CGPoint(x: cx - trunkWidthTop, y: trunkTop))
        path.addLine(to: CGPoint(x: cx + trunkWidthTop, y: trunkTop))
        path.addLine(to: CGPoint(x: cx + trunkWidthBottom, y: trunkBottom))
        path.closeSubpath()

        let branches: [(y: CGFloat, angle: CGFloat, len: CGFloat, side: CGFloat)] = [
            (0.38, -35, 0.28, -1),
            (0.45, -30, 0.22,  1),
            (0.52, -40, 0.20, -1),
            (0.58, -32, 0.18,  1),
            (0.66, -38, 0.14, -1),
            (0.72, -28, 0.12,  1),
        ]

        let branchWidth = w * 0.02

        for b in branches {
            let startY = h * b.y
            let startX = cx + (b.side * trunkWidthTop * 0.5)
            let radians = b.angle * .pi / 180
            let length = w * b.len
            let endX = startX + b.side * length * cos(radians)
            let endY = startY + length * sin(radians)

            let perpX = -sin(radians) * branchWidth
            let perpY = cos(radians) * branchWidth
            let tipWidth: CGFloat = 0.3

            path.move(to: CGPoint(x: startX - perpX, y: startY - perpY))
            path.addLine(to: CGPoint(x: endX - perpX * tipWidth, y: endY - perpY * tipWidth))
            path.addLine(to: CGPoint(x: endX + perpX * tipWidth, y: endY + perpY * tipWidth))
            path.addLine(to: CGPoint(x: startX + perpX, y: startY + perpY))
            path.closeSubpath()

            if b.len > 0.15 {
                let midX = startX + b.side * length * 0.6 * cos(radians)
                let midY = startY + length * 0.6 * sin(radians)
                let twigLen = length * 0.4
                let twigAngle = radians + b.side * (-0.5)
                let twigEndX = midX + twigLen * cos(twigAngle) * b.side
                let twigEndY = midY + twigLen * sin(twigAngle)
                let tw = branchWidth * 0.6

                path.move(to: CGPoint(x: midX - tw, y: midY))
                path.addLine(to: CGPoint(x: twigEndX, y: twigEndY))
                path.addLine(to: CGPoint(x: midX + tw, y: midY))
                path.closeSubpath()
            }
        }

        return path
    }
}
