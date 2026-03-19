import Foundation

enum ZodiacSign: Int, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    var symbol: String {
        switch self {
        case .aries: return "\u{2648}\u{FE0E}"
        case .taurus: return "\u{2649}\u{FE0E}"
        case .gemini: return "\u{264A}\u{FE0E}"
        case .cancer: return "\u{264B}\u{FE0E}"
        case .leo: return "\u{264C}\u{FE0E}"
        case .virgo: return "\u{264D}\u{FE0E}"
        case .libra: return "\u{264E}\u{FE0E}"
        case .scorpio: return "\u{264F}\u{FE0E}"
        case .sagittarius: return "\u{2650}\u{FE0E}"
        case .capricorn: return "\u{2651}\u{FE0E}"
        case .aquarius: return "\u{2652}\u{FE0E}"
        case .pisces: return "\u{2653}\u{FE0E}"
        }
    }

    var name: String {
        switch self {
        case .aries: return "Aries"
        case .taurus: return "Taurus"
        case .gemini: return "Gemini"
        case .cancer: return "Cancer"
        case .leo: return "Leo"
        case .virgo: return "Virgo"
        case .libra: return "Libra"
        case .scorpio: return "Scorpio"
        case .sagittarius: return "Sagittarius"
        case .capricorn: return "Capricorn"
        case .aquarius: return "Aquarius"
        case .pisces: return "Pisces"
        }
    }

    var element: Element {
        switch self {
        case .aries, .leo, .sagittarius: return .fire
        case .taurus, .virgo, .capricorn: return .earth
        case .gemini, .libra, .aquarius: return .air
        case .cancer, .scorpio, .pisces: return .water
        }
    }

    var modality: Modality {
        switch self {
        case .aries, .cancer, .libra, .capricorn: return .cardinal
        case .taurus, .leo, .scorpio, .aquarius: return .fixed
        case .gemini, .virgo, .sagittarius, .pisces: return .mutable
        }
    }

    enum Element: String, CaseIterable {
        case fire, earth, air, water

        var symbol: String {
            switch self {
            case .fire: return "\u{1F702}"
            case .earth: return "\u{1F703}"
            case .air: return "\u{1F701}"
            case .water: return "\u{1F704}"
            }
        }
    }

    enum Modality: String {
        case cardinal, fixed, mutable
    }
}

enum ZodiacSystem: String {
    case tropical
    case sidereal
}

struct ZodiacPosition {
    let sign: ZodiacSign
    let degree: Double
}

enum Planet: Int, CaseIterable {
    case sun, moon, mercury, venus, mars, jupiter, saturn

    var symbol: String {
        switch self {
        case .sun: return "\u{2609}\u{FE0E}"
        case .moon: return "\u{263D}\u{FE0E}"
        case .mercury: return "\u{263F}\u{FE0E}"
        case .venus: return "\u{2640}\u{FE0E}"
        case .mars: return "\u{2642}\u{FE0E}"
        case .jupiter: return "\u{2643}\u{FE0E}"
        case .saturn: return "\u{2644}\u{FE0E}"
        }
    }

    var name: String {
        switch self {
        case .sun: return "Sun"
        case .moon: return "Moon"
        case .mercury: return "Mercury"
        case .venus: return "Venus"
        case .mars: return "Mars"
        case .jupiter: return "Jupiter"
        case .saturn: return "Saturn"
        }
    }
}

struct PlanetaryPosition {
    let planet: Planet
    let longitude: Double
    let tropical: ZodiacPosition
    let sidereal: ZodiacPosition
    let isRetrograde: Bool
    let isIngress: Bool
}

struct PlanetaryHour {
    let planet: Planet
    let planetaryDay: Planet
}

struct ElementBalance {
    let counts: [ZodiacSign.Element: Int]

    var dominant: ZodiacSign.Element? {
        guard let maxCount = counts.values.max() else { return nil }
        let leaders = counts.filter { $0.value == maxCount }
        guard leaders.count == 1 else { return nil }
        return leaders.first?.key
    }
}

enum SeasonalMarker: String {
    case springEquinox, summerSolstice, autumnEquinox, winterSolstice
    case imbolc, beltane, lughnasadh, samhain

    var name: String {
        switch self {
        case .springEquinox: return "Spring Equinox"
        case .summerSolstice: return "Summer Solstice"
        case .autumnEquinox: return "Autumn Equinox"
        case .winterSolstice: return "Winter Solstice"
        case .imbolc: return "Imbolc"
        case .beltane: return "Beltane"
        case .lughnasadh: return "Lughnasadh"
        case .samhain: return "Samhain"
        }
    }
}

struct CelestialSnapshot {
    let positions: [PlanetaryPosition]
    let planetaryHour: PlanetaryHour
    let elementBalance: ElementBalance
    let system: ZodiacSystem
    let seasonalMarker: SeasonalMarker?

    func position(for planet: Planet) -> PlanetaryPosition? {
        positions.first { $0.planet == planet }
    }

    var retrogradePlanets: [Planet] {
        positions.filter { $0.isRetrograde }.map { $0.planet }
    }

    var ingressPlanets: [PlanetaryPosition] {
        positions.filter { $0.isIngress }
    }
}
