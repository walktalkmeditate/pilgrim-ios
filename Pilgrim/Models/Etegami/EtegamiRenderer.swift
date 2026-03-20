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
        let distanceText: String
        let durationText: String
        let elevationText: String?
    }

    private static let canvasSize = CGSize(width: 1080, height: 1920)
    private static let routeBounds = CGRect(x: 100, y: 200, width: 880, height: 900)

    static func render(input: Input) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 1. Paper flat fill
            input.paperColor.setFill()
            cgCtx.fill(CGRect(origin: .zero, size: canvasSize))

            // 2. Paper radial gradient
            let routeCenter = computeRouteCenter(input: input)
            drawPaperGradient(ctx: cgCtx, size: canvasSize, routeCenter: routeCenter, paperColor: input.paperColor)

            // 3. Paper grain
            drawPaperGrain(ctx: cgCtx, size: canvasSize, inkColor: input.inkColor)

            // 4. Inner border
            drawInnerBorder(ctx: cgCtx, size: canvasSize, inkColor: input.inkColor)

            // 5. Moon phase
            if let phase = input.moonPhase {
                let moonCenter = CGPoint(x: canvasSize.width - 120, y: 200)
                EtegamiMoonPhase.draw(
                    ctx: cgCtx, phase: phase,
                    center: moonCenter, radius: 28,
                    color: input.inkColor
                )
            }

            // 6-7. Route glow + crisp passes with start/end markers
            drawRoute(ctx: cgCtx, input: input)

            // 8. Seal glow
            let sealSize: CGFloat = 140
            let sealCenter = input.sealPosition
            drawSealGlow(ctx: cgCtx, center: sealCenter, radius: sealSize / 2, color: input.inkColor)

            // 9. Seal shadow + image
            let sealRect = CGRect(
                x: sealCenter.x - sealSize / 2,
                y: sealCenter.y - sealSize / 2,
                width: sealSize, height: sealSize
            )
            cgCtx.saveGState()
            cgCtx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.1).cgColor)
            input.sealImage.draw(in: sealRect)
            cgCtx.restoreGState()

            // 10. Haiku text
            drawHaiku(ctx: cgCtx, text: input.haikuText, inkColor: input.inkColor)

            // 11. Stats whisper
            drawStatsWhisper(ctx: cgCtx, input: input)

            // 12. Provenance
            drawProvenance(ctx: cgCtx, inkColor: input.inkColor)
        }
    }

    private static func drawRoute(ctx: CGContext, input: Input) {
        let projected = EtegamiRouteStroke.projectRoute(input.routePoints, into: routeBounds)
        guard projected.count > 1 else { return }

        let smoothed = EtegamiRouteStroke.smoothRoute(projected)

        let availableTop: CGFloat = 120
        let availableBottom: CGFloat = 1280
        let routeMinY = smoothed.map(\.y).min()!
        let routeMaxY = smoothed.map(\.y).max()!
        let routeMidY = (routeMinY + routeMaxY) / 2
        let targetMidY = (availableTop + availableBottom) / 2
        let offsetY = targetMidY - routeMidY

        let centered = smoothed.map { CGPoint(x: $0.x, y: $0.y + offsetY) }

        let segmentCount = centered.count - 1
        let smoothedAltitudes = EtegamiRouteStroke.interpolateAltitudes(
            input.altitudes, originalCount: projected.count, smoothedCount: centered.count
        )
        let tapers = EtegamiRouteStroke.computeTaperMultipliers(count: segmentCount)

        // Glow pass (single continuous path — no segment dots)
        EtegamiRouteStroke.drawGlow(
            ctx: ctx,
            projectedPoints: centered,
            lineWidth: 24,
            taperMultipliers: tapers,
            color: input.inkColor,
            opacity: 0.12
        )

        // Crisp pass
        let widths = EtegamiRouteStroke.computeStrokeWidths(
            altitudes: smoothedAltitudes, baseWidth: 8, count: segmentCount
        )
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

    // MARK: - Paper gradient

    private static func drawPaperGradient(ctx: CGContext, size: CGSize, routeCenter: CGPoint, paperColor: UIColor) {
        ctx.saveGState()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        paperColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lighterColor = UIColor(red: min(r + 0.03, 1), green: min(g + 0.03, 1), blue: min(b + 0.03, 1), alpha: 1)

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: [lighterColor.cgColor, paperColor.cgColor] as CFArray, locations: [0, 1]) {
            let maxRadius = max(size.width, size.height) * 0.7
            ctx.drawRadialGradient(gradient, startCenter: routeCenter, startRadius: 0, endCenter: routeCenter, endRadius: maxRadius, options: .drawsAfterEndLocation)
        }
        ctx.restoreGState()
    }

    // MARK: - Route center

    private static func computeRouteCenter(input: Input) -> CGPoint {
        let projected = EtegamiRouteStroke.projectRoute(input.routePoints, into: routeBounds)
        guard !projected.isEmpty else {
            return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }
        let avgX = projected.map(\.x).reduce(0, +) / CGFloat(projected.count)
        let avgY = projected.map(\.y).reduce(0, +) / CGFloat(projected.count)
        return CGPoint(x: avgX, y: avgY)
    }

    // MARK: - Seal glow

    private static func drawSealGlow(ctx: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        ctx.saveGState()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let glowColor = color.withAlphaComponent(0.08)
        let clearColor = color.withAlphaComponent(0.0)
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: [glowColor.cgColor, clearColor.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius * 2, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: - Text

    private static func drawHaiku(ctx: CGContext, text: String, inkColor: UIColor) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 8

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "CormorantGaramond-Light", size: 46) ?? UIFont(name: "Georgia", size: 46) ?? UIFont.systemFont(ofSize: 46),
            .foregroundColor: inkColor.withAlphaComponent(0.85),
            .paragraphStyle: paragraphStyle
        ]

        let maxWidth = canvasSize.width - 160
        let textRect = CGRect(x: 80, y: 1320, width: maxWidth, height: 360)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Stats whisper

    private static func drawStatsWhisper(ctx: CGContext, input: Input) {
        var parts = [input.distanceText, input.durationText]
        if let elevation = input.elevationText {
            parts.append(elevation)
        }
        let statsLine = parts.joined(separator: " \u{00B7} ")

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Lato-Regular", size: 16) ?? UIFont(name: "Helvetica", size: 16) ?? UIFont.systemFont(ofSize: 16),
            .foregroundColor: input.inkColor.withAlphaComponent(0.4),
            .paragraphStyle: paragraphStyle
        ]

        let maxWidth = canvasSize.width - 160
        let textRect = CGRect(x: 80, y: 1690, width: maxWidth, height: 30)
        (statsLine as NSString).draw(in: textRect, withAttributes: attrs)
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
