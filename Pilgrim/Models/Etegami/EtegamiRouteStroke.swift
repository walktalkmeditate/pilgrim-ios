import UIKit

enum EtegamiRouteStroke {

    struct ActivityMarker {
        enum MarkerType { case meditation, voice }
        let type: MarkerType
        let position: CGPoint
    }

    static func projectRoute(
        _ points: [(lat: Double, lon: Double)],
        into bounds: CGRect
    ) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let lats = points.map(\.lat)
        let lons = points.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let latRange = max(maxLat - minLat, 0.00001)
        let lonRange = max(maxLon - minLon, 0.00001)

        let padding: CGFloat = 40
        let innerBounds = bounds.insetBy(dx: padding, dy: padding)
        let scale = min(innerBounds.width / CGFloat(lonRange), innerBounds.height / CGFloat(latRange))

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2
        let cx = innerBounds.midX
        let cy = innerBounds.midY

        return points.map { p in
            CGPoint(
                x: cx + CGFloat(p.lon - midLon) * scale,
                y: cy - CGFloat(p.lat - midLat) * scale
            )
        }
    }

    static func computeStrokeWidths(
        altitudes: [Double], baseWidth: CGFloat, count: Int
    ) -> [CGFloat] {
        guard altitudes.count >= 2 else {
            return [CGFloat](repeating: baseWidth, count: count)
        }
        let minAlt = altitudes.min()!
        let maxAlt = altitudes.max()!
        let range = max(maxAlt - minAlt, 1.0)

        var widths: [CGFloat] = []
        for i in 0..<min(count, altitudes.count - 1) {
            let delta = altitudes[i + 1] - altitudes[i]
            let normalized = CGFloat(abs(delta) / range)
            let multiplier: CGFloat = delta > 0 ? 1.0 + normalized * 1.5 : 1.0 - normalized * 0.4
            widths.append(baseWidth * max(multiplier, 0.5))
        }
        while widths.count < count { widths.append(baseWidth) }
        return widths
    }

    static func computeTaperMultipliers(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let taperZone = max(Int(Double(count) * 0.1), 1)
        return (0..<count).map { i in
            if i < taperZone {
                return CGFloat(i) / CGFloat(taperZone)
            } else if i >= count - taperZone {
                return CGFloat(count - 1 - i) / CGFloat(taperZone)
            }
            return 1.0
        }
    }

    static func draw(
        ctx: CGContext,
        projectedPoints: [CGPoint],
        strokeWidths: [CGFloat],
        taperMultipliers: [CGFloat],
        color: UIColor,
        opacity: CGFloat,
        activityMarkers: [ActivityMarker]
    ) {
        guard projectedPoints.count > 1 else { return }

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for i in 0..<(projectedPoints.count - 1) {
            let width = strokeWidths[min(i, strokeWidths.count - 1)]
            let taper = taperMultipliers[min(i, taperMultipliers.count - 1)]
            let segmentWidth = width * taper
            let segmentOpacity = opacity * (0.6 + taper * 0.4)

            ctx.setStrokeColor(color.withAlphaComponent(segmentOpacity).cgColor)
            ctx.setLineWidth(segmentWidth)
            ctx.move(to: projectedPoints[i])
            ctx.addLine(to: projectedPoints[i + 1])
            ctx.strokePath()
        }

        ctx.restoreGState()

        for marker in activityMarkers {
            drawActivityMarker(ctx: ctx, marker: marker, color: color)
        }
    }

    private static func drawActivityMarker(
        ctx: CGContext, marker: ActivityMarker, color: UIColor
    ) {
        ctx.saveGState()
        switch marker.type {
        case .meditation:
            for ring in 1...3 {
                let r = CGFloat(ring) * 8
                let alpha = 0.15 / CGFloat(ring)
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(0.8)
                ctx.strokeEllipse(in: CGRect(
                    x: marker.position.x - r, y: marker.position.y - r,
                    width: r * 2, height: r * 2
                ))
            }
        case .voice:
            ctx.setStrokeColor(color.withAlphaComponent(0.2).cgColor)
            ctx.setLineWidth(0.6)
            let waveWidth: CGFloat = 12
            for i in 0..<5 {
                let x = marker.position.x - waveWidth / 2 + CGFloat(i) * 3
                let h: CGFloat = CGFloat([2, 5, 8, 5, 2][i])
                ctx.move(to: CGPoint(x: x, y: marker.position.y - h))
                ctx.addLine(to: CGPoint(x: x, y: marker.position.y + h))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
