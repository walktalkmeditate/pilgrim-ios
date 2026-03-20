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
        let displayDistance: String
    }

    private static let canvasSize = CGSize(width: 1080, height: 1920)
    private static let routeBounds = CGRect(x: 100, y: 200, width: 880, height: 900)

    static func render(input: Input) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 1. Paper background
            input.paperColor.setFill()
            cgCtx.fill(CGRect(origin: .zero, size: canvasSize))

            // 2. Paper grain
            drawPaperGrain(ctx: cgCtx, size: canvasSize, inkColor: input.inkColor)

            // 3. Inner border
            drawInnerBorder(ctx: cgCtx, size: canvasSize, inkColor: input.inkColor)

            // 4. Distance watermark (centered in route area)
            let routeCenter = CGPoint(x: routeBounds.midX, y: routeBounds.midY)
            drawDistanceWatermark(ctx: cgCtx, distance: input.displayDistance, center: routeCenter, inkColor: input.inkColor)

            // 5. Moon phase
            if let phase = input.moonPhase {
                let moonCenter = CGPoint(x: canvasSize.width - 120, y: 200)
                EtegamiMoonPhase.draw(
                    ctx: cgCtx, phase: phase,
                    center: moonCenter, radius: 28,
                    color: input.inkColor
                )
            }

            // 6. Route with start/end markers
            drawRoute(ctx: cgCtx, input: input)

            // 7. Seal (lower-left)
            let sealSize: CGFloat = 140
            let sealRect = CGRect(
                x: input.sealPosition.x - sealSize / 2,
                y: input.sealPosition.y - sealSize / 2,
                width: sealSize, height: sealSize
            )
            input.sealImage.draw(in: sealRect)

            // 8. Haiku text
            drawHaiku(ctx: cgCtx, text: input.haikuText, inkColor: input.inkColor)

            // 9. Provenance
            drawProvenance(ctx: cgCtx, inkColor: input.inkColor)
        }
    }

    private static func drawRoute(ctx: CGContext, input: Input) {
        let projected = EtegamiRouteStroke.projectRoute(input.routePoints, into: routeBounds)
        guard projected.count > 1 else { return }

        let smoothed = EtegamiRouteStroke.smoothRoute(projected)

        // Center the route vertically between y=120 and y=1280
        let availableTop: CGFloat = 120
        let availableBottom: CGFloat = 1280
        let routeMinY = smoothed.map(\.y).min()!
        let routeMaxY = smoothed.map(\.y).max()!
        let routeMidY = (routeMinY + routeMaxY) / 2
        let targetMidY = (availableTop + availableBottom) / 2
        let offsetY = targetMidY - routeMidY

        let centered = smoothed.map { CGPoint(x: $0.x, y: $0.y + offsetY) }

        let segmentCount = centered.count - 1
        let interpolatedAltitudes = EtegamiRouteStroke.interpolateAltitudes(
            input.altitudes, originalCount: projected.count, smoothedCount: centered.count
        )
        let widths = EtegamiRouteStroke.computeStrokeWidths(
            altitudes: interpolatedAltitudes, baseWidth: 10, count: segmentCount
        )
        let tapers = EtegamiRouteStroke.computeTaperMultipliers(count: segmentCount)

        EtegamiRouteStroke.draw(
            ctx: ctx,
            projectedPoints: centered,
            strokeWidths: widths,
            taperMultipliers: tapers,
            color: input.inkColor,
            opacity: 0.9,
            activityMarkers: input.activityMarkers
        )

        // Start marker: filled circle
        let startPoint = centered.first!
        ctx.saveGState()
        ctx.setFillColor(input.inkColor.withAlphaComponent(0.5).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: startPoint.x - 8, y: startPoint.y - 8,
            width: 16, height: 16
        ))
        ctx.restoreGState()

        // End marker: open circle
        let endPoint = centered.last!
        ctx.saveGState()
        ctx.setStrokeColor(input.inkColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(
            x: endPoint.x - 8, y: endPoint.y - 8,
            width: 16, height: 16
        ))
        ctx.restoreGState()
    }

    // MARK: - Paper grain

    private static func drawPaperGrain(ctx: CGContext, size: CGSize, inkColor: UIColor) {
        ctx.saveGState()
        var rng = SeededRNG(seed: 12345)
        let grainColor = inkColor.withAlphaComponent(0.025)
        ctx.setFillColor(grainColor.cgColor)
        let dotCount = 3000
        for _ in 0..<dotCount {
            let x = CGFloat.random(in: 0...size.width, using: &rng)
            let y = CGFloat.random(in: 0...size.height, using: &rng)
            let r = CGFloat.random(in: 0.5...1.5, using: &rng)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
    }

    // MARK: - Inner border

    private static func drawInnerBorder(ctx: CGContext, size: CGSize, inkColor: UIColor) {
        ctx.saveGState()
        let inset: CGFloat = 40
        ctx.setStrokeColor(inkColor.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2))
        ctx.restoreGState()
    }

    // MARK: - Distance watermark

    private static func drawDistanceWatermark(ctx: CGContext, distance: String, center: CGPoint, inkColor: UIColor) {
        let font = UIFont(name: "CormorantGaramond-Light", size: 220) ?? UIFont.systemFont(ofSize: 220, weight: .ultraLight)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: inkColor.withAlphaComponent(0.06)
        ]
        let str = NSAttributedString(string: distance, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    // MARK: - Text

    private static func drawHaiku(ctx: CGContext, text: String, inkColor: UIColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 8

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "CormorantGaramond-Light", size: 36) ?? UIFont(name: "Georgia", size: 36) ?? UIFont.systemFont(ofSize: 36),
            .foregroundColor: inkColor.withAlphaComponent(0.85),
            .paragraphStyle: paragraphStyle
        ]

        let maxWidth = canvasSize.width - 160
        let textRect = CGRect(x: 80, y: 1350, width: maxWidth, height: 300)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    private static func drawProvenance(ctx: CGContext, inkColor: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Lato-Regular", size: 14) ?? UIFont(name: "Helvetica", size: 14) ?? UIFont.systemFont(ofSize: 14),
            .foregroundColor: inkColor.withAlphaComponent(0.4)
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
