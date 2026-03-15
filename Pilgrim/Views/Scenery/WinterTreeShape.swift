import SwiftUI

struct WinterTreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w * 0.48

        addTrunk(to: &path, cx: cx, w: w, h: h)
        addBranch(to: &path, cx: cx, w: w, h: h, y: 0.32, length: 0.32, angle: -50, side: -1, hasTwig: true)
        addBranch(to: &path, cx: cx, w: w, h: h, y: 0.42, length: 0.26, angle: -45, side: 1, hasTwig: true)
        addBranch(to: &path, cx: cx, w: w, h: h, y: 0.50, length: 0.18, angle: -55, side: -1, hasTwig: false)
        addBranch(to: &path, cx: cx, w: w, h: h, y: 0.58, length: 0.20, angle: -40, side: 1, hasTwig: true)
        addBranch(to: &path, cx: cx, w: w, h: h, y: 0.68, length: 0.13, angle: -50, side: -1, hasTwig: false)
        addBranch(to: &path, cx: cx, w: w, h: h, y: 0.75, length: 0.10, angle: -42, side: 1, hasTwig: false)

        return path
    }

    private func addTrunk(to path: inout Path, cx: CGFloat, w: CGFloat, h: CGFloat) {
        let baseW = w * 0.07
        let topW = w * 0.025
        let top = h * 0.25

        path.move(to: CGPoint(x: cx - baseW, y: h))
        path.addQuadCurve(
            to: CGPoint(x: cx - topW, y: top),
            control: CGPoint(x: cx - baseW * 0.6, y: h * 0.55)
        )
        path.addLine(to: CGPoint(x: cx + topW, y: top))
        path.addQuadCurve(
            to: CGPoint(x: cx + baseW, y: h),
            control: CGPoint(x: cx + baseW * 0.4, y: h * 0.55)
        )
        path.closeSubpath()
    }

    private func addBranch(to path: inout Path, cx: CGFloat, w: CGFloat, h: CGFloat,
                           y: CGFloat, length: CGFloat, angle: CGFloat, side: CGFloat, hasTwig: Bool) {
        let startY = h * y
        let startX = cx + side * w * 0.03
        let rad = Double(angle) * .pi / 180
        let len = w * length
        let thickness = w * 0.022
        let cosRad = CGFloat(Foundation.cos(rad))
        let sinRad = CGFloat(Foundation.sin(rad))

        let midX = startX + side * len * 0.5
        let curveY = startY + len * sinRad * 0.5 - w * 0.02
        let endX = startX + side * len * cosRad
        let endY = startY + len * sinRad

        path.move(to: CGPoint(x: startX, y: startY - thickness))
        path.addQuadCurve(
            to: CGPoint(x: endX, y: endY),
            control: CGPoint(x: midX, y: curveY - thickness)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX, y: startY + thickness),
            control: CGPoint(x: midX, y: curveY + thickness)
        )
        path.closeSubpath()

        if hasTwig {
            let twigStart: CGFloat = 0.55
            let cosRad = CGFloat(Foundation.cos(Double(rad)))
            let sinRad = CGFloat(Foundation.sin(Double(rad)))
            let twigX = startX + side * len * twigStart * cosRad
            let twigY = startY + len * twigStart * sinRad
            let twigLen = len * 0.35
            let twigRad = Double(rad) + Double(side) * (-0.6)
            let twigEndX = twigX + side * twigLen * CGFloat(Foundation.cos(twigRad))
            let twigEndY = twigY + twigLen * CGFloat(Foundation.sin(twigRad))
            let tw = thickness * 0.5

            path.move(to: CGPoint(x: twigX - tw, y: twigY))
            path.addQuadCurve(
                to: CGPoint(x: twigEndX, y: twigEndY),
                control: CGPoint(x: (twigX + twigEndX) / 2, y: (twigY + twigEndY) / 2 - w * 0.01)
            )
            path.addLine(to: CGPoint(x: twigX + tw, y: twigY))
            path.closeSubpath()
        }
    }
}
