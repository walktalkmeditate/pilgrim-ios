import SwiftUI

struct GrassShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let bladeWidth = w * 0.08
        let positions: [(x: CGFloat, height: CGFloat)] = [
            (0.15, 0.6), (0.3, 0.8), (0.45, 0.5),
            (0.6, 0.9), (0.75, 0.65)
        ]

        for pos in positions {
            let baseX = w * pos.x
            let tipY = h * (1.0 - pos.height)

            path.move(to: CGPoint(x: baseX - bladeWidth / 2, y: h))
            path.addQuadCurve(
                to: CGPoint(x: baseX, y: tipY),
                control: CGPoint(x: baseX - bladeWidth, y: h * 0.5)
            )
            path.addQuadCurve(
                to: CGPoint(x: baseX + bladeWidth / 2, y: h),
                control: CGPoint(x: baseX + bladeWidth, y: h * 0.5)
            )
            path.closeSubpath()
        }

        return path
    }
}
