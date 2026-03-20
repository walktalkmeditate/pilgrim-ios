import UIKit

enum EtegamiMoonPhase {

    static func draw(
        ctx: CGContext,
        phase: LunarPhase,
        center: CGPoint,
        radius: CGFloat,
        color: UIColor
    ) {
        ctx.saveGState()

        let outlineAlpha: CGFloat = 0.08
        ctx.setStrokeColor(color.withAlphaComponent(outlineAlpha).cgColor)
        ctx.setLineWidth(0.8)
        ctx.strokeEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))

        let fillAlpha: CGFloat = 0.13
        ctx.setFillColor(color.withAlphaComponent(fillAlpha).cgColor)

        let illumination = phase.illumination
        let waxing = phase.isWaxing

        let path = CGMutablePath()
        let steps = 64

        for i in 0...steps {
            let angle = CGFloat(i) * (.pi / CGFloat(steps)) - .pi / 2
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }

        let terminatorX = CGFloat(2 * illumination - 1)
        for i in stride(from: steps, through: 0, by: -1) {
            let angle = CGFloat(i) * (.pi / CGFloat(steps)) - .pi / 2
            let y = center.y + radius * sin(angle)
            let x = center.x + terminatorX * radius * cos(angle)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()

        if waxing {
            ctx.addPath(path)
        } else {
            let mirroredTransform = CGAffineTransform(translationX: center.x, y: 0)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -center.x, y: 0)
            if let mirrored = path.copy(using: [mirroredTransform]) {
                ctx.addPath(mirrored)
            }
        }
        ctx.fillPath()

        ctx.restoreGState()
    }
}
