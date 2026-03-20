import CoreGraphics
import CoreText
import UIKit

enum SealRenderer {

    struct Input {
        let geometry: SealGeometry
        let color: UIColor
        let season: String
        let year: Int
        let timeOfDay: String
        let displayDistance: String
        let unitLabel: String
        let routePoints: [(lat: Double, lon: Double)]?
        let altitudes: [Double]?
        let weatherCondition: String?
    }

    static func render(input: Input, size: CGFloat = 512) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let ctx = context.cgContext
            let geo = input.geometry
            let cx = geo.center.x
            let cy = geo.center.y

            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: geo.rotation * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)

            drawWeatherTexture(ctx: ctx, input: input, size: size)
            drawGhostRoute(ctx: ctx, input: input, size: size)
            drawElevationRing(ctx: ctx, input: input, size: size)
            drawRings(ctx: ctx, input: input)
            drawRadialLines(ctx: ctx, input: input)
            drawArcSegments(ctx: ctx, input: input)
            drawDots(ctx: ctx, input: input)

            ctx.restoreGState()

            drawCurvedText(ctx: ctx, input: input, size: size)
            drawCenterText(ctx: ctx, input: input, size: size)
        }
    }

    // MARK: - Weather Texture

    private static func drawWeatherTexture(ctx: CGContext, input: Input, size: CGFloat) {
        guard let condition = input.weatherCondition?.lowercased(), !condition.isEmpty else { return }
        if condition == "clear" { return }

        let geo = input.geometry
        let cx = geo.center.x
        let cy = geo.center.y
        let outerR = geo.outerRadius
        let color = input.color

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        let seed: UInt64 = 42
        var rng = SeededRNG(seed: seed)

        switch condition {
        case "rain":
            for _ in 0..<60 {
                let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let dist = outerR * CGFloat.random(in: 0.9...1.05, using: &rng)
                let x = cx + cos(angle) * dist
                let y = cy + sin(angle) * dist
                let dotR = CGFloat.random(in: 0.5...1.5, using: &rng)
                ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 0.08).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
            }
        case "snow":
            for _ in 0..<40 {
                let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let dist = outerR * CGFloat.random(in: 0.92...1.04, using: &rng)
                let x = cx + cos(angle) * dist
                let y = cy + sin(angle) * dist
                let markAngle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let markLen: CGFloat = CGFloat.random(in: 1.5...3.0, using: &rng)
                ctx.setStrokeColor(UIColor(red: r, green: g, blue: b, alpha: 0.06).cgColor)
                ctx.setLineWidth(0.5)
                ctx.move(to: CGPoint(x: x - cos(markAngle) * markLen, y: y - sin(markAngle) * markLen))
                ctx.addLine(to: CGPoint(x: x + cos(markAngle) * markLen, y: y + sin(markAngle) * markLen))
                ctx.strokePath()
            }
        case "wind":
            for _ in 0..<30 {
                let angle = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let dist = outerR * CGFloat.random(in: 0.93...1.03, using: &rng)
                let x = cx + cos(angle) * dist
                let y = cy + sin(angle) * dist
                let streakLen = CGFloat.random(in: 3...8, using: &rng)
                ctx.setStrokeColor(UIColor(red: r, green: g, blue: b, alpha: 0.07).cgColor)
                ctx.setLineWidth(0.4)
                ctx.move(to: CGPoint(x: x - streakLen / 2, y: y))
                ctx.addLine(to: CGPoint(x: x + streakLen / 2, y: y))
                ctx.strokePath()
            }
        default:
            break
        }
    }

    // MARK: - Ghost Route

    private static func drawGhostRoute(ctx: CGContext, input: Input, size: CGFloat) {
        guard let points = input.routePoints, points.count >= 2 else { return }

        let geo = input.geometry
        let cx = geo.center.x
        let cy = geo.center.y
        let fitRadius = geo.outerRadius * 0.7

        let lats = points.map { $0.lat }
        let lons = points.map { $0.lon }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        let span = max(latSpan, lonSpan, 0.0001)

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        let scale = fitRadius * 2 / CGFloat(span)

        ctx.saveGState()
        ctx.setAlpha(0.055)
        ctx.setStrokeColor(input.color.cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for (i, point) in points.enumerated() {
            let x = cx + CGFloat(point.lon - midLon) * scale
            let y = cy - CGFloat(point.lat - midLat) * scale
            if i == 0 {
                ctx.move(to: CGPoint(x: x, y: y))
            } else {
                ctx.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Elevation Ring

    private static func drawElevationRing(ctx: CGContext, input: Input, size: CGFloat) {
        guard let altitudes = input.altitudes, altitudes.count > 10,
              input.geometry.rings.count > 2 else { return }

        let geo = input.geometry
        let cx = geo.center.x
        let cy = geo.center.y
        let baseRing = geo.rings[2]
        let baseRadius = baseRing.radius

        guard let minAlt = altitudes.min(), let maxAlt = altitudes.max(),
              maxAlt > minAlt else { return }

        let altRange = maxAlt - minAlt
        let amplitude = size * 0.03

        ctx.saveGState()
        ctx.setStrokeColor(input.color.withAlphaComponent(baseRing.opacity).cgColor)
        ctx.setLineWidth(baseRing.strokeWidth)

        let sampleCount = altitudes.count
        let path = CGMutablePath()

        for i in 0...sampleCount {
            let index = i % sampleCount
            let normalized = CGFloat((altitudes[index] - minAlt) / altRange)
            let offset = (normalized - 0.5) * 2 * amplitude
            let r = baseRadius + offset
            let angle = CGFloat(i) / CGFloat(sampleCount) * 2 * .pi - .pi / 2

            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Rings

    private static func drawRings(ctx: CGContext, input: Input) {
        let geo = input.geometry
        let cx = geo.center.x
        let cy = geo.center.y

        let hasElevationRing = input.altitudes != nil
            && (input.altitudes?.count ?? 0) > 10
            && geo.rings.count > 2

        for (i, ring) in geo.rings.enumerated() {
            if hasElevationRing && i == 2 { continue }

            ctx.saveGState()
            ctx.setStrokeColor(input.color.withAlphaComponent(ring.opacity).cgColor)
            ctx.setLineWidth(ring.strokeWidth)

            if let dashLen = ring.dashLength, let gapLen = ring.gapLength {
                ctx.setLineDash(phase: 0, lengths: [dashLen, gapLen])
            }

            ctx.strokeEllipse(in: CGRect(
                x: cx - ring.radius, y: cy - ring.radius,
                width: ring.radius * 2, height: ring.radius * 2
            ))
            ctx.restoreGState()
        }
    }

    // MARK: - Radial Lines

    private static func drawRadialLines(ctx: CGContext, input: Input) {
        let geo = input.geometry

        for line in geo.radialLines {
            ctx.saveGState()
            ctx.setStrokeColor(input.color.withAlphaComponent(line.opacity).cgColor)
            ctx.setLineWidth(line.strokeWidth)
            ctx.setLineCap(.round)
            ctx.move(to: line.innerPoint)
            ctx.addLine(to: line.outerPoint)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Arc Segments

    private static func drawArcSegments(ctx: CGContext, input: Input) {
        let geo = input.geometry
        let cx = geo.center.x
        let cy = geo.center.y

        for arc in geo.arcSegments {
            let startAngle = atan2(arc.startPoint.y - cy, arc.startPoint.x - cx)
            let endAngle = atan2(arc.endPoint.y - cy, arc.endPoint.x - cx)

            ctx.saveGState()
            ctx.setStrokeColor(input.color.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.8)
            ctx.setLineCap(.round)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: arc.radius,
                       startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Dots

    private static func drawDots(ctx: CGContext, input: Input) {
        for dot in input.geometry.dots {
            ctx.saveGState()
            ctx.setFillColor(input.color.withAlphaComponent(0.6).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: dot.center.x - dot.radius, y: dot.center.y - dot.radius,
                width: dot.radius * 2, height: dot.radius * 2
            ))
            ctx.restoreGState()
        }
    }

    // MARK: - Curved Text

    private static func drawCurvedText(ctx: CGContext, input: Input, size: CGFloat) {
        let geo = input.geometry
        let cx = geo.center.x
        let cy = geo.center.y
        let textRadius = geo.outerRadius * 0.88

        let topText = "PILGRIM \u{00B7} \(input.season.uppercased()) \(input.year)"
        let bottomText = "\(input.timeOfDay.uppercased()) WALK"

        let font = resolveFont(name: "Lato-Regular", size: size * 0.022)
        let color = input.color

        drawTextAlongArc(
            ctx: ctx, text: topText, font: font, color: color,
            center: CGPoint(x: cx, y: cy), radius: textRadius,
            startAngle: .pi, clockwise: false
        )

        drawTextAlongArc(
            ctx: ctx, text: bottomText, font: font, color: color,
            center: CGPoint(x: cx, y: cy), radius: textRadius,
            startAngle: 0, clockwise: true
        )
    }

    private static func drawTextAlongArc(
        ctx: CGContext, text: String, font: CTFont, color: UIColor,
        center: CGPoint, radius: CGFloat,
        startAngle: CGFloat, clockwise: Bool
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        var glyphEntries: [(glyph: CGGlyph, width: CGFloat, font: CTFont)] = []
        for run in runs {
            let runAttrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (runAttrs[kCTFontAttributeName] as! CTFont)

            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            CTRunGetAdvances(run, CFRange(location: 0, length: glyphCount), &advances)

            for i in 0..<glyphCount {
                glyphEntries.append((glyph: glyphs[i], width: advances[i].width, font: runFont))
            }
        }

        let totalWidth = glyphEntries.reduce(0) { $0 + $1.width }
        let totalArcAngle = totalWidth / radius
        let direction: CGFloat = clockwise ? 1 : -1

        var currentAngle = startAngle - direction * totalArcAngle / 2

        for entry in glyphEntries {
            let glyphArcAngle = entry.width / radius
            let midAngle = currentAngle + direction * glyphArcAngle / 2

            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)

            if clockwise {
                ctx.rotate(by: midAngle + .pi / 2)
            } else {
                ctx.rotate(by: midAngle - .pi / 2)
            }

            ctx.translateBy(x: 0, y: -radius)

            if clockwise {
                ctx.scaleBy(x: 1, y: -1)
            }

            ctx.textMatrix = .identity

            var glyph = entry.glyph
            var position = CGPoint(x: -entry.width / 2, y: 0)
            CTFontDrawGlyphs(entry.font, &glyph, &position, 1, ctx)

            ctx.restoreGState()
            currentAngle += direction * glyphArcAngle
        }
    }

    // MARK: - Center Text

    private static func drawCenterText(ctx: CGContext, input: Input, size: CGFloat) {
        let cx = input.geometry.center.x
        let cy = input.geometry.center.y

        let distanceFont = resolveFont(name: "CormorantGaramond-Light", size: size * 0.09)
        let unitFont = resolveFont(name: "Lato-Regular", size: size * 0.032)

        let distAttrs: [NSAttributedString.Key: Any] = [
            .font: distanceFont,
            .foregroundColor: input.color
        ]
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: unitFont,
            .foregroundColor: input.color.withAlphaComponent(0.7)
        ]

        let distStr = NSAttributedString(string: input.displayDistance, attributes: distAttrs)
        let unitStr = NSAttributedString(string: input.unitLabel, attributes: unitAttrs)

        let distLine = CTLineCreateWithAttributedString(distStr)
        let unitLine = CTLineCreateWithAttributedString(unitStr)

        let distBounds = CTLineGetBoundsWithOptions(distLine, .useOpticalBounds)
        let unitBounds = CTLineGetBoundsWithOptions(unitLine, .useOpticalBounds)

        let gap: CGFloat = size * 0.008
        let totalHeight = distBounds.height + gap + unitBounds.height
        let distY = cy - totalHeight / 2 + distBounds.height

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.scaleBy(x: 1, y: -1)

        ctx.textPosition = CGPoint(
            x: cx - distBounds.width / 2 - distBounds.origin.x,
            y: -distY
        )
        CTLineDraw(distLine, ctx)

        let unitY = distY + gap + unitBounds.height
        ctx.textPosition = CGPoint(
            x: cx - unitBounds.width / 2 - unitBounds.origin.x,
            y: -unitY
        )
        CTLineDraw(unitLine, ctx)

        ctx.restoreGState()
    }

    // MARK: - Font Resolution

    private static func resolveFont(name: String, size: CGFloat) -> CTFont {
        let candidate = CTFontCreateWithName(name as CFString, size, nil)
        let postScript = CTFontCopyPostScriptName(candidate) as String
        if postScript == name {
            return candidate
        }
        let fallbackName: String
        if name.contains("Cormorant") || name.contains("Garamond") {
            fallbackName = "Georgia"
        } else {
            fallbackName = "Helvetica"
        }
        return CTFontCreateWithName(fallbackName as CFString, size, nil)
    }

    // MARK: - Deterministic RNG

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
