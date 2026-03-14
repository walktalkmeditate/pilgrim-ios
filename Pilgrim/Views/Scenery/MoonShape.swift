import SwiftUI

struct MoonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: w * 0.45, y: h * 0.5)
        let outerR = min(w, h) * 0.45
        let innerR = outerR * 0.78
        let innerCenter = CGPoint(x: center.x + outerR * 0.5, y: center.y - outerR * 0.08)

        var outer = Path()
        outer.addArc(center: center, radius: outerR,
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        var inner = Path()
        inner.addArc(center: innerCenter, radius: innerR,
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        return outer.subtracting(inner)
    }
}
