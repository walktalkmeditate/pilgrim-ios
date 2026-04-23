import UIKit

enum ShiftIntensity {
    case full
    case moderate
    case minimal
}

struct SeasonalAdjustment {
    let hueDelta: CGFloat
    let saturationMultiplier: CGFloat
    let brightnessMultiplier: CGFloat
}

struct SeasonalColorEngine {

    static var debugDateOverride: Date?

    static func seasonalTransform(for date: Date, hemisphere: Hemisphere) -> SeasonalAdjustment {
        let dayOfYear = adjustedDayOfYear(for: date, hemisphere: hemisphere)
        let params = Constants.Seasonal.self

        let springPhase = seasonalWeight(dayOfYear: dayOfYear, peakDay: params.springPeakDay, spread: params.spread)
        let summerPhase = seasonalWeight(dayOfYear: dayOfYear, peakDay: params.summerPeakDay, spread: params.spread)
        let autumnPhase = seasonalWeight(dayOfYear: dayOfYear, peakDay: params.autumnPeakDay, spread: params.spread)
        let winterPhase = seasonalWeight(dayOfYear: dayOfYear, peakDay: params.winterPeakDay, spread: params.spread)

        let hue = springPhase * params.springHue
            + summerPhase * params.summerHue
            + autumnPhase * params.autumnHue
            + winterPhase * params.winterHue

        let saturation = springPhase * params.springSaturation
            + summerPhase * params.summerSaturation
            + autumnPhase * params.autumnSaturation
            + winterPhase * params.winterSaturation

        let brightness = springPhase * params.springBrightness
            + summerPhase * params.summerBrightness
            + autumnPhase * params.autumnBrightness
            + winterPhase * params.winterBrightness

        return SeasonalAdjustment(
            hueDelta: hue,
            saturationMultiplier: 1.0 + saturation,
            brightnessMultiplier: 1.0 + brightness
        )
    }

    static func applySeasonalShift(
        to color: UIColor,
        intensity: ShiftIntensity,
        on date: Date,
        hemisphere: Hemisphere
    ) -> UIColor {
        let scale: CGFloat
        switch intensity {
        case .full: scale = 1.0
        case .moderate: scale = 0.4
        case .minimal: scale = 0.1
        }

        let adjustment = seasonalTransform(for: date, hemisphere: hemisphere)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let newHue = (hue + adjustment.hueDelta * scale).truncatingRemainder(dividingBy: 1.0)
        let newSaturation = clamp(saturation * (1.0 + (adjustment.saturationMultiplier - 1.0) * scale), 0, 1)
        let newBrightness = clamp(brightness * (1.0 + (adjustment.brightnessMultiplier - 1.0) * scale), 0, 1)

        return UIColor(
            hue: newHue < 0 ? newHue + 1.0 : newHue,
            saturation: newSaturation,
            brightness: newBrightness,
            alpha: alpha
        )
    }

    static func seasonalColor(named name: String, intensity: ShiftIntensity) -> UIColor {
        let date = debugDateOverride ?? Date()
        let hemisphere = storedHemisphere

        guard UIColor(named: name) != nil else {
            return .gray
        }

        return UIColor { traitCollection in
            let base = UIColor(named: name)!
            let resolved = base.resolvedColor(with: traitCollection)
            return applySeasonalShift(to: resolved, intensity: intensity, on: date, hemisphere: hemisphere)
        }
    }

    static func seasonalColor(
        named name: String,
        intensity: ShiftIntensity,
        on date: Date,
        hemisphere: Hemisphere? = nil
    ) -> UIColor {
        let hem = hemisphere ?? storedHemisphere

        guard UIColor(named: name) != nil else {
            return .gray
        }

        return UIColor { traitCollection in
            let base = UIColor(named: name)!
            let resolved = base.resolvedColor(with: traitCollection)
            return applySeasonalShift(to: resolved, intensity: intensity, on: date, hemisphere: hem)
        }
    }

    // MARK: - Private

    private static var storedHemisphere: Hemisphere {
        guard let raw = UserPreferences.hemisphereOverride.value else {
            return .northern
        }
        return Hemisphere(rawValue: raw) ?? .northern
    }

    private static func adjustedDayOfYear(for date: Date, hemisphere: Hemisphere) -> Int {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        switch hemisphere {
        case .northern:
            return dayOfYear
        case .southern:
            return (dayOfYear + 182) % 365 + 1
        }
    }

    private static func seasonalWeight(dayOfYear: Int, peakDay: Int, spread: CGFloat) -> CGFloat {
        let distance = min(
            abs(CGFloat(dayOfYear - peakDay)),
            CGFloat(365) - abs(CGFloat(dayOfYear - peakDay))
        )
        let normalized = distance / spread
        let weight = max(0, cos(normalized * .pi / 2))
        return weight * weight
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }
}
