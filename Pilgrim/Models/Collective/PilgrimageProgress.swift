import Foundation

struct PilgrimageProgress {
    let message: String
    let distanceKm: Double

    private static let routes: [(name: String, km: Double)] = [
        ("Kumano Kodo", 40),
        ("Via Francigena stage", 100),
        ("Camino de Santiago", 800),
        ("Shikoku 88 Temples", 1_200),
        ("Te Araroa", 3_000),
        ("Appalachian Trail", 3_500),
        ("the Moon", 384_400),
    ]

    static func from(distanceKm: Double) -> PilgrimageProgress {
        if distanceKm < 10 {
            return PilgrimageProgress(message: "The path is beginning.", distanceKm: distanceKm)
        }
        if distanceKm < 40 {
            return PilgrimageProgress(message: "The first steps, taken together.", distanceKm: distanceKm)
        }

        for route in routes.reversed() {
            if distanceKm >= route.km {
                let times = distanceKm / route.km
                if times >= 2 {
                    return PilgrimageProgress(
                        message: "Together, \(Int(times)) \(route.name)s walked.",
                        distanceKm: distanceKm
                    )
                } else {
                    return PilgrimageProgress(
                        message: "Together, one \(route.name) complete.",
                        distanceKm: distanceKm
                    )
                }
            }
        }

        let progress = distanceKm / routes[0].km
        let pct = Int(progress * 100)
        return PilgrimageProgress(
            message: "\(pct)% of our first \(routes[0].name).",
            distanceKm: distanceKm
        )
    }
}

struct CollectiveMilestone {
    let number: Int
    let message: String

    static func forNumber(_ number: Int, totalWalks: Int) -> CollectiveMilestone {
        let message: String
        switch number {
        case 108:
            message = "108 walks. One for each bead on the mala."
        case 1_080:
            message = "1,080 walks. The mala, turned ten times."
        case 2_160:
            message = "2,160 walks. One full age of the zodiac."
        case 10_000:
            message = "10,000 walks. 万 — all things."
        case 33_333:
            message = "33,333 walks. The Saigoku pilgrimage, a thousandfold."
        case 88_000:
            message = "88,000 walks. Shikoku's 88 temples, a thousand times over."
        case 108_000:
            message = "108,000 walks. The great mala, complete."
        default:
            message = "\(number.formatted()) walks. You were one of them."
        }
        return CollectiveMilestone(number: number, message: message)
    }
}
