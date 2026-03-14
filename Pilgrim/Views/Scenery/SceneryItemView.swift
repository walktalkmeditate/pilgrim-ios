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
        case .lantern: lanternView
        case .butterfly: butterflyView
        case .moon: moonView
        case .mountain: mountainView
        case .torii: toriiView
        }
    }

    // MARK: - Tree — organic sway, falling leaves, bare winter branches

    private var treeView: some View {
        let month = Calendar.current.component(.month, from: walkDate)
        let seasonalColor = treeSeasonalColor
        let isWinter = month == 12 || month <= 2
        let isAutumn = (9...11).contains(month)
        let isSpring = (3...5).contains(month)

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let sway1 = sin(time * 0.6) * 1.5
            let sway2 = sin(time * 1.3) * 0.8
            let gust = sin(time * 0.2) * sin(time * 0.2) * 2.5
            let totalSway = sway1 + sway2 + gust

            ZStack {
                if isWinter {
                    winterBranches(time: time, totalSway: totalSway, color: seasonalColor)
                } else {
                    canopy(time: time, totalSway: totalSway, color: seasonalColor)
                }

                if isAutumn {
                    fallingLeaves(time: time, color: Color(uiColor: SeasonalColorEngine.seasonalColor(named: "rust", intensity: .full, on: walkDate)))
                }

                if isSpring {
                    fallingLeaves(time: time, color: Color(red: 1.0, green: 0.7, blue: 0.8))
                }
            }
        }
    }

    private func canopy(time: Double, totalSway: Double, color: Color) -> some View {
        let dappleX = sin(time * 0.4) * size * 0.15
        let dappleY = cos(time * 0.3) * size * 0.1

        return ZStack {
            TreeShape()
                .fill(color.opacity(0.12))
                .frame(width: size * 1.08, height: size * 1.08)
                .offset(x: totalSway * 0.4 + 1.5, y: 1)
                .blur(radius: 1.2)

            TreeShape()
                .fill(color.opacity(0.3))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(totalSway * 0.5), anchor: .bottom)

            TreeShape()
                .fill(color.opacity(0.12))
                .frame(width: size * 0.88, height: size * 0.88)
                .offset(x: -1, y: 1)
                .rotationEffect(.degrees(totalSway * 0.3), anchor: .bottom)

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: size * 0.3, height: size * 0.3)
                .blur(radius: 4)
                .offset(x: dappleX, y: dappleY - size * 0.15)
        }
    }

    private func winterBranches(time: Double, totalSway: Double, color: Color) -> some View {
        let s = size
        return ZStack {
            // Trunk
            Rectangle()
                .fill(color.opacity(0.25))
                .frame(width: s * 0.08, height: s * 0.5)
                .offset(y: s * 0.22)

            // Branches — stroked lines radiating out
            ForEach(0..<5, id: \.self) { i in
                let angle = -60.0 + Double(i) * 30.0
                let length = s * (0.2 + CGFloat(i % 3) * 0.08)
                let branchSway = sin(time * (0.5 + Double(i) * 0.15)) * 2

                Rectangle()
                    .fill(color.opacity(0.2))
                    .frame(width: length, height: s * 0.025)
                    .rotationEffect(.degrees(angle + branchSway + totalSway * 0.3), anchor: .leading)
                    .offset(x: s * 0.04, y: -s * 0.05 + CGFloat(i) * s * 0.08)
            }
        }
    }

    private func fallingLeaves(time: Double, color: Color) -> some View {
        let leaves: [(phase: Double, speed: Double, xOff: Double)] = [
            (0.0, 0.7, -0.3), (1.5, 0.9, 0.2), (3.0, 0.6, 0.1), (4.2, 0.8, -0.15)
        ]

        return ForEach(Array(leaves.enumerated()), id: \.offset) { _, leaf in
            let t = (time * leaf.speed + leaf.phase).truncatingRemainder(dividingBy: 5.0)
            let progress = t / 5.0
            let leafX = sin(t * 2.0) * size * 0.2 + size * CGFloat(leaf.xOff)
            let leafY = -size * 0.3 + CGFloat(progress) * size * 0.9
            let leafOpacity = progress < 0.1 ? progress / 0.1 : (progress > 0.7 ? (1 - progress) / 0.3 : 1.0)
            let spin = t * 120

            Circle()
                .fill(color.opacity(0.4 * leafOpacity))
                .frame(width: size * 0.06, height: size * 0.06)
                .rotationEffect(.degrees(spin))
                .offset(x: leafX, y: leafY)
        }
    }

    private var treeSeasonalColor: Color {
        let month = Calendar.current.component(.month, from: walkDate)
        switch month {
        case 3...5: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "moss", intensity: .full, on: walkDate))
        case 6...8: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full, on: walkDate))
        case 9...11: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate))
        default: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "ink", intensity: .moderate, on: walkDate))
        }
    }

    // MARK: - Grass — individual blade physics, seed heads, dewdrops, wind ripple

    private var grassView: some View {
        let month = Calendar.current.component(.month, from: walkDate)
        let isWinter = month == 12 || month <= 2
        let grassColor: Color = isWinter
            ? Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate))
            : Color(uiColor: SeasonalColorEngine.seasonalColor(named: "moss", intensity: .full, on: walkDate))
        let hour = Calendar.current.component(.hour, from: walkDate)
        let hasDew = hour >= 5 && hour < 9

        let blades: [(xPos: CGFloat, height: CGFloat, hasSeed: Bool)] = [
            (0.1, 0.55, false), (0.28, 0.8, true), (0.45, 0.5, false),
            (0.62, 0.9, true), (0.78, 0.65, true)
        ]

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                ForEach(Array(blades.enumerated()), id: \.offset) { i, blade in
                    let delay = Double(i) * 0.3
                    let sway = sin(time * 1.0 + delay) * blade.height * 3
                    let gust = sin(time * 0.3 + delay * 0.5) * sin(time * 0.3) * 2
                    let totalSway = sway + gust
                    let bladeH = size * blade.height
                    let baseX = size * (blade.xPos - 0.5)

                    Capsule()
                        .fill(grassColor.opacity(0.25))
                        .frame(width: size * 0.04, height: bladeH)
                        .rotationEffect(.degrees(totalSway * 1.5), anchor: .bottom)
                        .offset(x: baseX, y: size * 0.2 - bladeH * 0.3)

                    if blade.hasSeed {
                        Circle()
                            .fill(grassColor.opacity(0.35))
                            .frame(width: size * 0.07, height: size * 0.07)
                            .offset(
                                x: baseX + sin(.init(totalSway * .pi / 180)) * bladeH * 0.4,
                                y: size * 0.2 - bladeH * 0.75
                            )
                    }

                    if hasDew {
                        Circle()
                            .fill(.white.opacity(0.4))
                            .frame(width: size * 0.035, height: size * 0.035)
                            .offset(
                                x: baseX + sin(.init(totalSway * .pi / 180)) * bladeH * 0.35,
                                y: size * 0.2 - bladeH * 0.65
                            )
                            .phaseAnimator([false, true]) { content, phase in
                                content.opacity(phase ? 0.6 : 0.2)
                            } animation: { _ in .easeInOut(duration: 1.5) }
                    }
                }
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: - Lantern — flickering warm glow

    private var lanternView: some View {
        let month = Calendar.current.component(.month, from: walkDate)
        let isWinter = month == 12 || month <= 2
        let glowColor = isWinter
            ? Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate))
            : Color(uiColor: SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full, on: walkDate))

        return TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let flicker1 = sin(time * 3.7) * 0.15
            let flicker2 = sin(time * 5.3) * 0.08
            let flicker3 = sin(time * 7.1) * 0.05
            let glowIntensity = 0.35 + flicker1 + flicker2 + flicker3

            ZStack {
                Circle()
                    .fill(glowColor.opacity(glowIntensity * 0.3))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .blur(radius: 6)
                    .offset(y: -size * 0.1)

                LanternShape()
                    .fill(tintColor.opacity(0.1))
                    .frame(width: size * 1.06, height: size * 1.06)
                    .offset(x: 1.5, y: 1.5)
                    .blur(radius: 1.2)

                LanternShape()
                    .fill(tintColor.opacity(0.35))
                    .frame(width: size, height: size)

                LanternWindowShape()
                    .fill(glowColor.opacity(glowIntensity))
                    .frame(width: size, height: size)
                    .blur(radius: 0.5)
            }
        }
    }

    // MARK: - Butterfly — gentle wing flap, drifting

    private var butterflyView: some View {
        let wingColor = butterflySeasonalColor

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let wingFlap = (sin(time * 3.8) + 1) / 2
            let drift = sin(time * 0.4) * 3
            let wobble = sin(time * 0.7) * 4

            ZStack {
                Ellipse()
                    .fill(wingColor.opacity(0.2))
                    .frame(width: size * 0.45, height: size * 0.35)
                    .scaleEffect(y: 0.3 + wingFlap * 0.7)
                    .offset(x: -size * 0.22, y: -size * 0.05)

                Ellipse()
                    .fill(wingColor.opacity(0.15))
                    .frame(width: size * 0.35, height: size * 0.25)
                    .scaleEffect(y: 0.4 + wingFlap * 0.6)
                    .offset(x: -size * 0.18, y: size * 0.12)

                Ellipse()
                    .fill(wingColor.opacity(0.2))
                    .frame(width: size * 0.45, height: size * 0.35)
                    .scaleEffect(y: 0.3 + wingFlap * 0.7)
                    .offset(x: size * 0.22, y: -size * 0.05)

                Ellipse()
                    .fill(wingColor.opacity(0.15))
                    .frame(width: size * 0.35, height: size * 0.25)
                    .scaleEffect(y: 0.4 + wingFlap * 0.6)
                    .offset(x: size * 0.18, y: size * 0.12)

                Capsule()
                    .fill(wingColor.opacity(0.3))
                    .frame(width: size * 0.05, height: size * 0.3)
            }
            .offset(x: wobble, y: drift)
            .rotationEffect(.degrees(wobble * 0.5))
        }
    }

    private var butterflySeasonalColor: Color {
        let month = Calendar.current.component(.month, from: walkDate)
        switch month {
        case 3...5: return Color(red: 1.0, green: 0.7, blue: 0.8)
        case 6...8: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate))
        case 9...11: return Color(uiColor: SeasonalColorEngine.seasonalColor(named: "rust", intensity: .full, on: walkDate))
        default: return Color.white.opacity(0.8)
        }
    }

    // MARK: - Moon — clouds, stars, moonlight rays, unique phase

    private var moonView: some View {
        let phaseScale = 0.85 + CGFloat(abs(walkDate.hashValue % 30)) / 100.0

        return TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                moonRays(time: time)

                Circle()
                    .fill(tintColor.opacity(0.05))
                    .frame(width: size * 1.8, height: size * 1.8)
                    .blur(radius: 8)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 0.8 : 0.4)
                    } animation: { _ in .easeInOut(duration: 3.0) }

                MoonShape()
                    .fill(tintColor.opacity(0.1))
                    .frame(width: size * 1.06 * phaseScale, height: size * 1.06 * phaseScale)
                    .offset(x: 1, y: 1)
                    .blur(radius: 1.5)

                MoonShape()
                    .fill(tintColor.opacity(0.35))
                    .frame(width: size * phaseScale, height: size * phaseScale)

                MoonShape()
                    .fill(.white.opacity(0.1))
                    .frame(width: size * 0.92 * phaseScale, height: size * 0.92 * phaseScale)
                    .offset(x: -1, y: -1)

                stars(time: time)
                driftingClouds(time: time)
            }
        }
    }

    private func moonRays(time: Double) -> some View {
        let rayPulse = (sin(time * 0.3) + 1) / 2 * 0.04 + 0.02

        return ForEach(0..<6, id: \.self) { i in
            let angle = Double(i) * 60.0 + sin(time * 0.2) * 5
            Rectangle()
                .fill(.white.opacity(rayPulse))
                .frame(width: size * 0.02, height: size * 0.6)
                .blur(radius: 2)
                .rotationEffect(.degrees(angle), anchor: .bottom)
                .offset(y: -size * 0.15)
        }
    }

    private func stars(time: Double) -> some View {
        let starData: [(x: CGFloat, y: CGFloat, speed: Double)] = [
            (-0.35, -0.3, 2.1), (0.4, -0.35, 3.0), (-0.25, 0.3, 1.7),
            (0.35, 0.25, 2.5), (-0.4, 0.05, 1.9), (0.15, -0.4, 2.8)
        ]

        return ForEach(Array(starData.enumerated()), id: \.offset) { _, star in
            let twinkle = (sin(time * star.speed) + 1) / 2
            Circle()
                .fill(.white.opacity(0.15 + twinkle * 0.25))
                .frame(width: size * 0.04, height: size * 0.04)
                .offset(x: size * star.x, y: size * star.y)
        }
    }

    private func driftingClouds(time: Double) -> some View {
        let clouds: [(yOff: CGFloat, speed: Double, width: CGFloat)] = [
            (-0.05, 0.15, 0.5), (0.1, 0.1, 0.35)
        ]

        return ForEach(Array(clouds.enumerated()), id: \.offset) { _, cloud in
            let drift = sin(time * cloud.speed) * size * 0.3
            let fadeEdge = (cos(time * cloud.speed * 0.8) + 1) / 2 * 0.06 + 0.03

            Ellipse()
                .fill(Color.parchment.opacity(fadeEdge))
                .frame(width: size * cloud.width, height: size * 0.12)
                .blur(radius: 3)
                .offset(x: drift, y: size * cloud.yOff)
        }
    }

    // MARK: - Mountain — layered range with mist, alpenglow, shimmering snow

    private var mountainView: some View {
        let month = Calendar.current.component(.month, from: walkDate)
        let hasSnow = month <= 3 || month >= 11
        let hour = Calendar.current.component(.hour, from: walkDate)
        let isMorning = hour >= 5 && hour < 10

        return TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let mistDrift = sin(time * 0.3) * size * 0.15
            let mistOpacity = (sin(time * 0.2) + 1) / 2 * 0.12 + 0.04

            ZStack {
                if isMorning {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate)).opacity(0.15),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.7
                            )
                        )
                        .frame(width: size * 1.4, height: size * 1.0)
                        .offset(y: -size * 0.2)
                }

                MountainShape()
                    .fill(tintColor.opacity(0.08))
                    .frame(width: size * 1.2, height: size * 1.1)
                    .offset(x: -size * 0.1, y: size * 0.05)
                    .blur(radius: 2.5)

                MountainShape()
                    .fill(tintColor.opacity(0.15))
                    .frame(width: size * 1.05, height: size * 1.02)
                    .offset(x: size * 0.08, y: size * 0.02)
                    .blur(radius: 1)

                MountainShape()
                    .fill(tintColor.opacity(0.3))
                    .frame(width: size, height: size)

                Ellipse()
                    .fill(tintColor.opacity(mistOpacity))
                    .frame(width: size * 0.7, height: size * 0.1)
                    .blur(radius: 3)
                    .offset(x: mistDrift, y: size * 0.1)

                if hasSnow {
                    Triangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: size * 0.22, height: size * 0.13)
                        .offset(x: size * 0.1, y: -size * 0.38)
                        .blur(radius: 0.5)
                        .phaseAnimator([false, true]) { content, phase in
                            content.opacity(phase ? 0.3 : 0.15)
                        } animation: { _ in .easeInOut(duration: 2.0) }

                    Triangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: size * 0.14, height: size * 0.09)
                        .offset(x: -size * 0.08, y: -size * 0.28)
                        .blur(radius: 0.3)
                        .phaseAnimator([false, true]) { content, phase in
                            content.opacity(phase ? 0.2 : 0.08)
                        } animation: { _ in .easeInOut(duration: 2.5) }
                }
            }
        }
    }

    // MARK: - Torii — gateway glow, shimenawa rope, fluttering shide

    private var toriiView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(uiColor: SeasonalColorEngine.seasonalColor(named: "dawn", intensity: .full, on: walkDate)).opacity(0.08),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.4
                        )
                    )
                    .frame(width: size * 0.6, height: size * 0.8)
                    .offset(y: -size * 0.05)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 1.0 : 0.5)
                    } animation: { _ in .easeInOut(duration: 3.5) }

                Ellipse()
                    .fill(tintColor.opacity(0.06))
                    .frame(width: size * 0.9, height: size * 0.15)
                    .blur(radius: 2)
                    .offset(y: size * 0.48)

                ToriiGateShape()
                    .fill(tintColor.opacity(0.08))
                    .frame(width: size * 1.05, height: size * 1.05)
                    .offset(x: 1.5, y: 2)
                    .blur(radius: 1.5)

                ToriiGateShape()
                    .fill(tintColor.opacity(0.35))
                    .frame(width: size, height: size)

                ropeAndShide(time: time)
            }
        }
    }

    private func ropeAndShide(time: Double) -> some View {
        let ropeY = size * 0.28
        let leftX = -size * 0.22
        let rightX = size * 0.22

        let shidePositions: [CGFloat] = [-0.12, 0.0, 0.12]

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: leftX, y: ropeY))
                path.addQuadCurve(
                    to: CGPoint(x: rightX, y: ropeY),
                    control: CGPoint(x: 0, y: ropeY + size * 0.06)
                )
            }
            .stroke(tintColor.opacity(0.2), lineWidth: 1)

            ForEach(Array(shidePositions.enumerated()), id: \.offset) { i, xPos in
                let flutter = sin(time * 2.0 + Double(i) * 1.2) * 2.5
                let stripX = size * xPos

                Path { path in
                    path.move(to: CGPoint(x: stripX, y: ropeY + size * 0.03))
                    path.addLine(to: CGPoint(x: stripX + CGFloat(flutter) * 0.3, y: ropeY + size * 0.08))
                    path.addLine(to: CGPoint(x: stripX + size * 0.03, y: ropeY + size * 0.08))
                    path.addLine(to: CGPoint(x: stripX + size * 0.03 + CGFloat(flutter) * 0.5, y: ropeY + size * 0.14))
                    path.addLine(to: CGPoint(x: stripX - size * 0.01, y: ropeY + size * 0.14))
                    path.addLine(to: CGPoint(x: stripX - size * 0.01 + CGFloat(flutter) * 0.4, y: ropeY + size * 0.19))
                }
                .stroke(.white.opacity(0.2), lineWidth: 0.8)
            }
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
