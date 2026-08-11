import Foundation

enum RouteTrimmer {

    /// Shaves `meters` of walked distance off each end of the route so a
    /// shared page never reveals a doorstep. Walks shorter than 4x the trim
    /// distance share untrimmed — mid-walk geometry is all they have.
    static func trim(_ route: [SharePayload.RoutePoint], meters: Double) -> [SharePayload.RoutePoint] {
        guard meters > 0, route.count > 3 else { return route }
        var cumulative: [Double] = [0]
        for i in 1..<route.count {
            cumulative.append(cumulative[i - 1] + haversineMeters(route[i - 1], route[i]))
        }
        let total = cumulative[route.count - 1]
        guard total >= meters * 4 else { return route }

        var start = 0
        while start < route.count - 1 && cumulative[start] < meters { start += 1 }
        var end = route.count - 1
        while end > 0 && total - cumulative[end] < meters { end -= 1 }
        guard end > start else { return route }
        return Array(route[start...end])
    }

    /// Whether a 150m trim can actually apply — the UI uses this to say
    /// "too short to trim" instead of silently promising protection.
    static func canTrim(_ route: [SharePayload.RoutePoint], meters: Double) -> Bool {
        guard meters > 0, route.count > 3 else { return false }
        var total = 0.0
        for i in 1..<route.count { total += haversineMeters(route[i - 1], route[i]) }
        return total >= meters * 4
    }

    private static func haversineMeters(_ a: SharePayload.RoutePoint, _ b: SharePayload.RoutePoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let la = a.lat * .pi / 180
        let lb = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(h))
    }
}
