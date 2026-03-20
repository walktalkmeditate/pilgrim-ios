import UIKit

enum EtegamiRenderer {

    struct Input {
        let routePoints: [(lat: Double, lon: Double)]
        let altitudes: [Double]
        let activityMarkers: [EtegamiRouteStroke.ActivityMarker]
        let sealImage: UIImage
        let sealPosition: CGPoint
        let haikuText: String
        let moonPhase: LunarPhase?
        let timeOfDay: String
        let inkColor: UIColor
        let paperColor: UIColor
    }

    private static let canvasSize = CGSize(width: 1080, height: 1920)
    private static let routeBounds = CGRect(x: 80, y: 300, width: 920, height: 900)

    static func render(input: Input) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            input.paperColor.setFill()
            cgCtx.fill(CGRect(origin: .zero, size: canvasSize))

            if let phase = input.moonPhase {
                let moonCenter = CGPoint(x: canvasSize.width - 120, y: 200)
                EtegamiMoonPhase.draw(
                    ctx: cgCtx, phase: phase,
                    center: moonCenter, radius: 28,
                    color: input.inkColor
                )
            }

            drawRoute(ctx: cgCtx, input: input)

            let sealSize: CGFloat = 80
            let sealRect = CGRect(
                x: input.sealPosition.x - sealSize / 2,
                y: input.sealPosition.y - sealSize / 2,
                width: sealSize, height: sealSize
            )
            input.sealImage.draw(in: sealRect)

            drawHaiku(ctx: cgCtx, text: input.haikuText, inkColor: input.inkColor)
            drawProvenance(ctx: cgCtx, inkColor: input.inkColor)
        }
    }

    private static func drawRoute(ctx: CGContext, input: Input) {
        let projected = EtegamiRouteStroke.projectRoute(input.routePoints, into: routeBounds)
        guard projected.count > 1 else { return }

        let segmentCount = projected.count - 1
        let widths = EtegamiRouteStroke.computeStrokeWidths(
            altitudes: input.altitudes, baseWidth: 4, count: segmentCount
        )
        let tapers = EtegamiRouteStroke.computeTaperMultipliers(count: segmentCount)

        EtegamiRouteStroke.draw(
            ctx: ctx,
            projectedPoints: projected,
            strokeWidths: widths,
            taperMultipliers: tapers,
            color: input.inkColor,
            opacity: 0.7,
            activityMarkers: input.activityMarkers
        )
    }

    private static func drawHaiku(ctx: CGContext, text: String, inkColor: UIColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 8

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "CormorantGaramond-Light", size: 36) ?? UIFont.systemFont(ofSize: 36),
            .foregroundColor: inkColor.withAlphaComponent(0.6),
            .paragraphStyle: paragraphStyle
        ]

        let maxWidth = canvasSize.width - 160
        let textRect = CGRect(x: 80, y: 1350, width: maxWidth, height: 300)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    private static func drawProvenance(ctx: CGContext, inkColor: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Lato-Regular", size: 14) ?? UIFont.systemFont(ofSize: 14),
            .foregroundColor: inkColor.withAlphaComponent(0.25)
        ]

        let text = "pilgrimapp.org" as NSString
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(
            x: canvasSize.width - size.width - 60,
            y: canvasSize.height - size.height - 60
        )
        text.draw(at: origin, withAttributes: attrs)
    }
}
