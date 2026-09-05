import SwiftUI

/// The first line of any moment, in the preview and on the walk card alike:
/// its glyph in a disc, what they did here, and one line of where.
struct WayMomentHeader: View {
    let moment: WayMoment
    let subline: String?
    var compact = false
    /// Degrees clockwise from the walker's own heading to the moment; the
    /// direction tick turns with the walker. Nil hides it.
    var tick: Double?

    var body: some View {
        HStack(alignment: .top, spacing: compact ? Constants.UI.Padding.small : Constants.UI.Padding.normal) {
            ZStack {
                Circle().fill(Color.parchment).frame(width: compact ? 36 : 52, height: compact ? 36 : 52)
                Image(systemName: Self.glyph(for: moment))
                    .font(compact ? Constants.Typography.body : Constants.Typography.heading)
                    .foregroundColor(.stone)
            }
            VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                Text(Self.kicker(for: moment))
                    .font(compact ? Constants.Typography.body : Constants.Typography.heading)
                    .foregroundColor(.ink)
                if let localName = Self.localName(for: moment) {
                    Text(localName)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                if let subline {
                    HStack(spacing: 4) {
                        if let tick {
                            Image(systemName: "location.north.fill")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.stone)
                                .rotationEffect(.degrees(tick))
                                .animation(.easeOut(duration: 0.25), value: tick)
                                .accessibilityHidden(true)
                        }
                        Text(subline).font(Constants.Typography.caption).foregroundColor(.fog)
                    }
                }
            }
        }
    }

    static func glyph(for moment: WayMoment) -> String {
        switch moment.kind {
        case .voice(_, _, let kind, _): return kind == .ambient ? "wind" : "waveform"
        case .photo: return "photo"
        case .rest: return "cup.and.saucer"
        case .meditation: return "circle.circle"
        case .waypoint(_, let icon): return UIImage(systemName: icon) == nil ? "mappin" : icon
        }
    }

    static func kicker(for moment: WayMoment) -> String {
        switch moment.kind {
        case .voice(_, _, let kind, _): return kind == .ambient ? "the sound of this place" : "spoken here"
        case .photo: return "what they saw here"
        case .rest(let minutes): return "they rested here \(minutes) minutes"
        case .meditation(let minutes, let isEstimate):
            return isEstimate ? "they sat here about \(minutes) minutes" : "they sat here for \(minutes) minutes"
        case .waypoint(let label, _): return label
        }
    }

    /// The languages a place's own name is worth showing in, in the order
    /// the routes run: Basque and Galician before Spanish on the caminos,
    /// Japanese for Shikoku. A name equal to the label says nothing twice.
    static let localNameOrder = ["eu", "gl", "es", "fr", "ja", "pt", "it", "de"]

    static func localName(for moment: WayMoment) -> String? {
        guard let names = moment.names else { return nil }
        let label = kicker(for: moment)
        for code in localNameOrder {
            guard let name = names[code], !name.isEmpty, name != label else { continue }
            return name
        }
        return nil
    }

    /// A card body for a place: the dataset's own words when it has them,
    /// otherwise the shortest true thing. A stage has no "they".
    static func placeCopy(for moment: WayMoment, isStage: Bool) -> String {
        if let text = moment.text, !text.isEmpty { return text }
        return isStage ? "A place on the way." : "A place they marked."
    }

    /// "here" within a few strides, otherwise the distance still to cover in
    /// the walker's own unit; the walk card's subline, with the street name
    /// when the Way has one.
    static func relation(distanceMeters: Double?, place: String?) -> String? {
        var parts: [String] = []
        if let distanceMeters {
            parts.append(distanceMeters < 30 ? "here" : "\(WayDistance.string(meters: distanceMeters)) away")
        }
        if let place, !place.isEmpty { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Walking-scale distances in the unit the walker chose in Settings: metres
/// up to a kilometre, feet up to a tenth of a mile, then one decimal.
enum WayDistance {

    static func string(meters: Double, unit: UnitLength = UserPreferences.distanceMeasurementType.safeValue) -> String {
        let meters = max(0, meters)
        if unit == .miles {
            let miles = meters / 1609.344
            if miles < 0.1 { return "\(Int((meters * 3.28084).rounded())) ft" }
            return String(format: "%.1f mi", miles)
        }
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", meters / 1000)
    }
}

/// "stage 1 of 33 · 24 km · hard" — what stands where a shared walk shows
/// the day it was walked. A stage's own date is the build's timestamp and
/// means nothing to the walker.
enum WayStageLine {

    static func line(for way: Way) -> String? {
        way.stage.map(line(for:))
    }

    static func line(for stage: WayStage) -> String {
        var parts = ["stage \(stage.index + 1) of \(stage.count)",
                     StatsHelper.string(for: stage.distanceKm * 1000, unit: UnitLength.meters, type: .distance)]
        if !stage.difficulty.isEmpty { parts.append(stage.difficulty) }
        return parts.joined(separator: " · ")
    }
}
