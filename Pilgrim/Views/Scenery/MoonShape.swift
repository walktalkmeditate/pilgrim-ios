import SwiftUI

struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let outerRadius = min(w, h) * 0.45
        let center = CGPoint(x: w * 0.5, y: h * 0.5)

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(-60),
            endAngle: .degrees(200),
            clockwise: false
        )

        let innerCenter = CGPoint(x: center.x + outerRadius * 0.35, y: center.y - outerRadius * 0.15)
        let innerRadius = outerRadius * 0.8

        path.addArc(
            center: innerCenter,
            radius: innerRadius,
            startAngle: .degrees(200),
            endAngle: .degrees(-60),
            clockwise: true
        )

        path.closeSubpath()

        return path
    }
}
