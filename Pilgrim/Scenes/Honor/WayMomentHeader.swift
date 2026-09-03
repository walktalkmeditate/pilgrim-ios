import SwiftUI

/// The first line of any moment, in the preview and on the walk card alike:
/// its glyph in a disc, what they did here, and one line of where.
struct WayMomentHeader: View {
    let moment: WayMoment
    let subline: String?
    var compact = false

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
                if let subline {
                    Text(subline).font(Constants.Typography.caption).foregroundColor(.fog)
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

    /// "here" within a few strides, otherwise the distance still to cover;
    /// the walk card's subline, with the street name when the Way has one.
    static func relation(distanceMeters: Double?, place: String?) -> String? {
        var parts: [String] = []
        if let distanceMeters {
            parts.append(distanceMeters < 30 ? "here" : "\(Int(distanceMeters.rounded())) m away")
        }
        if let place, !place.isEmpty { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
