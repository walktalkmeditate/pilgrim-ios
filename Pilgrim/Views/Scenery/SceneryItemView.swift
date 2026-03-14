import SwiftUI

struct SceneryItemView: View {

    let type: SceneryType
    let tintColor: Color
    let size: CGFloat
    let walkDate: Date

    var body: some View {
        switch type {
        case .tree: treeView
        case .grass: grassView
        case .pond: pondView
        case .moon: moonView
        case .mountain: mountainView
        case .stone: stoneView
        case .torii: toriiView
        }
    }

    // MARK: - Tree — sways gently, seasonal canopy

    private var treeView: some View {
        let seasonalColor = treeSeasonalColor
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let sway = sin(time * 0.8) * 2.0

            ZStack {
                TreeShape()
                    .fill(seasonalColor.opacity(0.15))
                    .frame(width: size * 1.08, height: size * 1.08)
                    .offset(x: sway * 0.5 + 1.5, y: 1)
                    .blur(radius: 1)

                TreeShape()
                    .fill(seasonalColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(sway * 0.5), anchor: .bottom)

                TreeShape()
                    .fill(seasonalColor.opacity(0.15))
                    .frame(width: size * 0.9, height: size * 0.9)
                    .offset(x: -1, y: 1)
                    .rotationEffect(.degrees(sway * 0.3), anchor: .bottom)
            }
        }
    }

    private var treeSeasonalColor: Color {
        let month = Calendar.current.component(.month, from: walkDate)
        switch month {
        case 3...5: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "moss", intensity: .full, on: walkDate))
        case 6...8: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "moss", intensity: .full, on: walkDate))
        case 9...11: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate))
        default: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "ink", intensity: .moderate, on: walkDate))
        }
    }

    // MARK: - Grass — waves in the wind

    private var grassView: some View {
        let month = Calendar.current.component(.month, from: walkDate)
        let isWinter = month == 12 || month <= 2
        let grassColor: Color = isWinter
            ? Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate))
            : Color(uiColor: SeasonalColorEngine.seasonalColor(named: "moss", intensity: .full, on: walkDate))

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wave = sin(time * 1.2) * 1.5

            ZStack {
                GrassShape()
                    .fill(grassColor.opacity(0.12))
                    .frame(width: size * 1.1, height: size * 1.1)
                    .offset(x: 2, y: 1)
                    .blur(radius: 1.2)

                GrassShape()
                    .fill(grassColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .offset(x: wave)

                GrassShape()
                    .fill(grassColor.opacity(0.18))
                    .frame(width: size * 0.85, height: size * 0.85)
                    .offset(x: wave * 1.3 + 1)
            }
        }
    }

    // MARK: - Pond — shimmering ripples

    private var pondView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let ripple = sin(time * 1.5) * 0.03

            ZStack {
                PondShape()
                    .fill(tintColor.opacity(0.1))
                    .frame(width: size * 1.15, height: size * 1.15)
                    .blur(radius: 2)

                PondShape()
                    .fill(
                        LinearGradient(
                            colors: [tintColor.opacity(0.25), tintColor.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size, height: size)
                    .scaleEffect(1.0 + ripple)

                Ellipse()
                    .stroke(tintColor.opacity(0.1), lineWidth: 0.5)
                    .frame(width: size * 0.5, height: size * 0.2)
                    .scaleEffect(1.0 + ripple * 2)
                    .offset(y: -size * 0.05)
            }
        }
    }

    // MARK: - Moon — breathing glow

    private var moonView: some View {
        ZStack {
            Circle()
                .fill(tintColor.opacity(0.06))
                .frame(width: size * 1.8, height: size * 1.8)
                .blur(radius: 8)
                .phaseAnimator([false, true]) { content, phase in
                    content.opacity(phase ? 0.8 : 0.4)
                } animation: { _ in .easeInOut(duration: 3.0) }

            MoonShape()
                .fill(tintColor.opacity(0.12))
                .frame(width: size * 1.06, height: size * 1.06)
                .offset(x: 1, y: 1)
                .blur(radius: 1.5)

            MoonShape()
                .fill(tintColor.opacity(0.35))
                .frame(width: size, height: size)

            MoonShape()
                .fill(.white.opacity(0.1))
                .frame(width: size * 0.92, height: size * 0.92)
                .offset(x: -1, y: -1)
        }
    }

    // MARK: - Mountain — layered with fog cap

    private var mountainView: some View {
        let month = Calendar.current.component(.month, from: walkDate)
        let hasSnow = month <= 3 || month >= 11

        return ZStack {
            MountainShape()
                .fill(tintColor.opacity(0.1))
                .frame(width: size * 1.1, height: size * 1.1)
                .offset(x: 2, y: 2)
                .blur(radius: 1.5)

            MountainShape()
                .fill(tintColor.opacity(0.3))
                .frame(width: size, height: size)

            MountainShape()
                .fill(tintColor.opacity(0.15))
                .frame(width: size * 0.95, height: size * 0.95)
                .offset(x: -1)

            if hasSnow {
                Triangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: size * 0.2, height: size * 0.12)
                    .offset(x: size * 0.1, y: -size * 0.38)
                    .blur(radius: 0.5)
            }
        }
    }

    // MARK: - Stone — eternal, multi-layer

    private var stoneView: some View {
        ZStack {
            StoneShape()
                .fill(tintColor.opacity(0.1))
                .frame(width: size * 1.1, height: size * 1.1)
                .offset(x: 1.5, y: 1.5)
                .blur(radius: 1.2)

            StoneShape()
                .fill(tintColor.opacity(0.3))
                .frame(width: size, height: size)

            StoneShape()
                .fill(tintColor.opacity(0.12))
                .frame(width: size * 0.8, height: size * 0.75)
                .offset(x: -1, y: 1)
        }
    }

    // MARK: - Torii — solid with subtle shadow

    private var toriiView: some View {
        ZStack {
            ToriiGateShape()
                .fill(tintColor.opacity(0.08))
                .frame(width: size * 1.05, height: size * 1.05)
                .offset(x: 1.5, y: 2)
                .blur(radius: 1.5)

            ToriiGateShape()
                .fill(tintColor.opacity(0.35))
                .frame(width: size, height: size)

            ToriiGateShape()
                .fill(tintColor.opacity(0.1))
                .frame(width: size * 0.96, height: size * 0.96)
                .offset(x: -0.5)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
