import SwiftUI

struct FootprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Left foot — slightly rotated oval, offset left
        let leftCenter = CGPoint(x: w * 0.35, y: h * 0.5)
        let ovalW: CGFloat = w * 0.22
        let ovalH: CGFloat = h * 0.7
        path.addEllipse(in: CGRect(
            x: leftCenter.x - ovalW / 2,
            y: leftCenter.y - ovalH / 2,
            width: ovalW,
            height: ovalH
        ))

        // Right foot — slightly rotated oval, offset right
        let rightCenter = CGPoint(x: w * 0.65, y: h * 0.5)
        path.addEllipse(in: CGRect(
            x: rightCenter.x - ovalW / 2,
            y: rightCenter.y - ovalH / 2,
            width: ovalW,
            height: ovalH
        ))

        return path
    }
}
