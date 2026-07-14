import SwiftUI

extension InkScrollView {

    // MARK: - Scenery

    func sceneryForDot(snapshot: WalkSnapshot, viewportHeight: CGFloat, opacity: Double) -> AnyView? {
        guard let placement = SceneryGenerator.scenery(for: snapshot) else {
            return nil
        }

        let baseTint = Color(uiColor: SeasonalColorEngine.seasonalColor(
            named: placement.tintColorName,
            intensity: .full,
            on: snapshot.startDate
        ))
        let tintColor = Self.weatherAdjustedColor(baseTint, condition: snapshot.weatherCondition)

        let baseSize: CGFloat = 32
        var h: UInt64 = 14695981039346656037
        withUnsafeBytes(of: snapshot.id) { $0.forEach { h = (h ^ UInt64($0)) &* 1099511628211 } }
        let sizeVariation = CGFloat(h % 20) / 20.0
        let size = baseSize + sizeVariation * 24

        let xOffset: CGFloat = placement.side == .left ? -40 - size / 2 : 40 + size / 2

        // Dot-relative placement. The scenery is hosted inside WalkDotView's
        // ZStack, which is framed to a ~50pt box and then positioned at the
        // dot — so content-space `.position` coordinates get applied twice
        // (box position + local position ≈ 2× the dot's y), landing scenery
        // beside the wrong dot near the top of the scroll and below the
        // viewport everywhere deeper. An offset from the dot's center is
        // correct in any host geometry.
        //
        // The item ages with its walk (the dot's own fade) and drifts by
        // its type's depth weight — horizon barely moves, foreground most.
        let parallax = placement.type.parallaxWeight
        // Seeking gates refuse the age fade — old stone grows older,
        // not fainter. Everything else dims with its walk.
        let sceneryOpacity = placement.gateKind == .seeking ? 1.0 : opacity
        return AnyView(
            SceneryItemView(
                type: placement.type,
                tintColor: tintColor,
                size: size,
                walkDate: snapshot.startDate,
                stones: placement.stones,
                gateKind: placement.gateKind
            )
            .opacity(sceneryOpacity)
            .offset(x: xOffset + placement.offset, y: -4)
            .visualEffect { content, proxy in
                let frame = proxy.frame(in: .global)
                let screenMid = viewportHeight / 2
                let distFromCenter = (frame.midY - screenMid) / screenMid
                return content.offset(x: distFromCenter * parallax)
            }
            .accessibilityHidden(true)
        )
    }

    // MARK: - Weather mood

    private static func weatherAdjustedColor(_ color: Color, condition: String?) -> Color {
        guard let condStr = condition,
              let cond = WeatherCondition(rawValue: condStr) else { return color }

        let uiColor = UIColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        switch cond {
        case .clear:
            h += 0.02
            b = min(b * 1.05, 1)
        case .partlyCloudy:
            break
        case .overcast:
            s *= 0.85
            b *= 0.95
        case .lightRain:
            h -= 0.01
            b *= 0.88
        case .heavyRain:
            h -= 0.02
            b *= 0.80
        case .thunderstorm:
            s *= 0.7
            b *= 0.75
        case .snow:
            h += 0.03
            b = min(b * 1.05, 1)
            s *= 0.85
        case .fog:
            s *= 0.6
            b *= 0.9
        case .wind:
            break
        case .haze:
            h += 0.02
            s *= 0.85
        }

        return Color(hue: Double((h + 1).truncatingRemainder(dividingBy: 1)),
                      saturation: Double(max(0, min(s, 1))),
                      brightness: Double(max(0, min(b, 1))),
                      opacity: Double(a))
    }
}
