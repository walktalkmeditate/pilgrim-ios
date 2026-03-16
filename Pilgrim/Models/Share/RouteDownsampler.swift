import Foundation

enum RouteDownsampler {

    static func downsample(
        _ points: [SharePayload.RoutePoint],
        maxPoints: Int = 200
    ) -> [SharePayload.RoutePoint] {
        guard points.count > maxPoints else { return points }
        let result = ramerDouglasPeucker(points, epsilon: findEpsilon(points, target: maxPoints))
        guard result.count <= maxPoints else {
            return strideSample(result, target: maxPoints)
        }
        return result
    }

    private static func strideSample(
        _ points: [SharePayload.RoutePoint],
        target: Int
    ) -> [SharePayload.RoutePoint] {
        let step = Double(points.count - 1) / Double(target - 1)
        var result: [SharePayload.RoutePoint] = []
        for i in 0..<(target - 1) {
            result.append(points[Int((Double(i) * step).rounded())])
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func ramerDouglasPeucker(
        _ points: [SharePayload.RoutePoint],
        epsilon: Double
    ) -> [SharePayload.RoutePoint] {
        guard points.count > 2 else { return points }

        var maxDist = 0.0
        var maxIndex = 0

        let first = points[0]
        let last = points[points.count - 1]

        for i in 1..<(points.count - 1) {
            let dist = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
            if dist > maxDist {
                maxDist = dist
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = ramerDouglasPeucker(Array(points[...maxIndex]), epsilon: epsilon)
            let right = ramerDouglasPeucker(Array(points[maxIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }

        return [first, last]
    }

    private static func perpendicularDistance(
        _ point: SharePayload.RoutePoint,
        lineStart: SharePayload.RoutePoint,
        lineEnd: SharePayload.RoutePoint
    ) -> Double {
        let dx = lineEnd.lon - lineStart.lon
        let dy = lineEnd.lat - lineStart.lat
        let lengthSq = dx * dx + dy * dy

        guard lengthSq > 0 else {
            let px = point.lon - lineStart.lon
            let py = point.lat - lineStart.lat
            return sqrt(px * px + py * py)
        }

        let t = max(0, min(1,
            ((point.lon - lineStart.lon) * dx + (point.lat - lineStart.lat) * dy) / lengthSq
        ))

        let projLon = lineStart.lon + t * dx
        let projLat = lineStart.lat + t * dy
        let px = point.lon - projLon
        let py = point.lat - projLat

        return sqrt(px * px + py * py)
    }

    private static func findEpsilon(
        _ points: [SharePayload.RoutePoint],
        target: Int
    ) -> Double {
        var low = 0.0
        var high = 0.01

        for _ in 0..<20 {
            let mid = (low + high) / 2
            let result = ramerDouglasPeucker(points, epsilon: mid)
            if result.count > target {
                low = mid
            } else {
                high = mid
            }
        }

        return high
    }
}
