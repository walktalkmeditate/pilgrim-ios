import UIKit

enum EtegamiRouteStroke {

    struct ActivityMarker {
        enum MarkerType { case meditation, voice }
        let type: MarkerType
        let position: CGPoint
        let routeIndex: Int?
    }

    static func smoothRoute(_ points: [CGPoint], subdivisions: Int = 8) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        var smoothed: [CGPoint] = []
        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[min(i + 1, points.count - 1)]
            let p3 = points[min(i + 2, points.count - 1)]
            for s in 0..<subdivisions {
                let t = CGFloat(s) / CGFloat(subdivisions)
                let tt = t * t
                let ttt = tt * t
                let x = 0.5 * ((2 * p1.x) +
                               (-p0.x + p2.x) * t +
                               (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * tt +
                               (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * ttt)
                let y = 0.5 * ((2 * p1.y) +
                               (-p0.y + p2.y) * t +
                               (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * tt +
                               (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * ttt)
                smoothed.append(CGPoint(x: x, y: y))
            }
        }
        smoothed.append(points.last!)
        return smoothed
    }

    static func interpolateAltitudes(_ altitudes: [Double], originalCount: Int, smoothedCount: Int) -> [Double] {
        guard altitudes.count >= 2, originalCount >= 2, smoothedCount > 0 else {
            return [Double](repeating: altitudes.first ?? 0, count: smoothedCount)
        }
        var result: [Double] = []
        for i in 0..<smoothedCount {
            let t = Double(i) / Double(max(smoothedCount - 1, 1)) * Double(altitudes.count - 1)
            let lower = min(Int(t), altitudes.count - 2)
            let frac = t - Double(lower)
            result.append(altitudes[lower] + frac * (altitudes[lower + 1] - altitudes[lower]))
        }
        return result
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
            let multiplier: CGFloat = delta > 0 ? 1.0 + normalized * 1.0 : 1.0 - normalized * 0.3
            widths.append(baseWidth * min(max(multiplier, 0.5), 2.0))
        }
        while widths.count < count { widths.append(baseWidth) }
        return widths
    }

    static func computeTaperMultipliers(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let taperZone = max(Int(Double(count) * 0.1), 1)
        return (0..<count).map { i in
            if i < taperZone {
                return max(CGFloat(i) / CGFloat(taperZone), 0.15)
            } else if i >= count - taperZone {
                return max(CGFloat(count - 1 - i) / CGFloat(taperZone), 0.15)
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
            var resolved = marker
            if let idx = marker.routeIndex {
                let smoothedIdx = min(idx * 8, projectedPoints.count - 1)
                resolved = ActivityMarker(type: marker.type, position: projectedPoints[smoothedIdx], routeIndex: idx)
            }
            drawActivityMarker(ctx: ctx, marker: resolved, color: color)
        }
    }

    private static func drawActivityMarker(
        ctx: CGContext, marker: ActivityMarker, color: UIColor
    ) {
        ctx.saveGState()
        switch marker.type {
        case .meditation:
            for ring in 1...3 {
                let r = CGFloat(ring) * 14
                let alpha = 0.3 / CGFloat(ring)
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(0.8)
                ctx.strokeEllipse(in: CGRect(
                    x: marker.position.x - r, y: marker.position.y - r,
                    width: r * 2, height: r * 2
                ))
            }
        case .voice:
            ctx.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(1.2)
            let waveWidth: CGFloat = 28
            let spacing: CGFloat = waveWidth / 5
            for i in 0..<5 {
                let x = marker.position.x - waveWidth / 2 + CGFloat(i) * spacing
                let h: CGFloat = CGFloat([4, 10, 16, 10, 4][i])
                ctx.move(to: CGPoint(x: x, y: marker.position.y - h))
                ctx.addLine(to: CGPoint(x: x, y: marker.position.y + h))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
