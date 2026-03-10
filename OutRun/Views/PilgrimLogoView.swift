import SwiftUI

struct PilgrimLogoShape: Shape {

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        let strokeWidth = w * 0.08
        let centerX = w * 0.5
        let centerY = h * 0.42
        let radius = w * 0.32

        // Stem: slight curve from bottom rising up to meet the enso
        let stemBottom = CGPoint(x: centerX - w * 0.02, y: h * 0.92)
        let stemTop = CGPoint(x: centerX - radius * cos(.pi * 0.17), y: centerY + radius * sin(.pi * 0.17))
        let stemControl = CGPoint(x: centerX - w * 0.04, y: h * 0.65)

        // Outer stem edge
        path.move(to: CGPoint(x: stemBottom.x - strokeWidth * 0.6, y: stemBottom.y))
        path.addQuadCurve(
            to: CGPoint(x: stemTop.x - strokeWidth * 0.35, y: stemTop.y),
            control: CGPoint(x: stemControl.x - strokeWidth * 0.5, y: stemControl.y)
        )

        // Enso arc (clockwise ~300 degrees, leaving gap at bottom-left)
        let startAngle = Angle.degrees(200)
        let endAngle = Angle.degrees(140)

        // Outer arc
        path.addArc(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius + strokeWidth * 0.5,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        // Inner arc (reverse direction for fill)
        path.addArc(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius - strokeWidth * 0.5,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        // Inner stem edge back down
        path.addQuadCurve(
            to: CGPoint(x: stemBottom.x + strokeWidth * 0.4, y: stemBottom.y),
            control: CGPoint(x: stemControl.x + strokeWidth * 0.3, y: stemControl.y)
        )

        path.closeSubpath()
        return path
    }
}

struct PilgrimLogoView: View {

    var size: CGFloat = 80
    var color: Color = .stone
    var animated: Bool = false

    @State private var progress: CGFloat = 0

    var body: some View {
        PilgrimLogoShape()
            .trim(from: 0, to: animated ? progress : 1)
            .fill(color)
            .frame(width: size, height: size)
            .onAppear {
                if animated {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        progress = 1
                    }
                }
            }
    }
}
