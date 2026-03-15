import Foundation

struct LunarPhase {

    let illumination: Double
    let age: Double
    let name: String

    static func current(date: Date = Date()) -> LunarPhase {
        let age = lunarAge(for: date)
        let illumination = lunarIllumination(age: age)
        let name = phaseName(age: age)
        return LunarPhase(illumination: illumination, age: age, name: name)
    }

    var isWaxing: Bool { age < Self.synodicMonth / 2 }

    private static let synodicMonth = 29.53058770576
    private static let knownNewMoon = DateComponents(
        calendar: .init(identifier: .gregorian),
        timeZone: TimeZone(identifier: "UTC"),
        year: 2000, month: 1, day: 6, hour: 18, minute: 14
    ).date!

    private static func lunarAge(for date: Date) -> Double {
        let daysSinceRef = date.timeIntervalSince(knownNewMoon) / 86400
        let age = daysSinceRef.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    private static func lunarIllumination(age: Double) -> Double {
        0.5 * (1 - cos(2 * .pi * age / synodicMonth))
    }

    private static func phaseName(age: Double) -> String {
        let eighth = synodicMonth / 8
        switch age {
        case 0 ..< eighth:                    return "New Moon"
        case eighth ..< (2 * eighth):         return "Waxing Crescent"
        case (2 * eighth) ..< (3 * eighth):   return "First Quarter"
        case (3 * eighth) ..< (4 * eighth):   return "Waxing Gibbous"
        case (4 * eighth) ..< (5 * eighth):   return "Full Moon"
        case (5 * eighth) ..< (6 * eighth):   return "Waning Gibbous"
        case (6 * eighth) ..< (7 * eighth):   return "Last Quarter"
        default:                              return "Waning Crescent"
        }
    }
}
