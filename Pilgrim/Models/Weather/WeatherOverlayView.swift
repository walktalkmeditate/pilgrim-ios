import SwiftUI

struct WeatherOverlayView: View {

    let condition: WeatherCondition?

    private var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        if let condition {
            ZStack {
                staticTint(for: condition)
                if !reduceMotion {
                    particleLayer(for: condition)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Static Tints

    @ViewBuilder
    private func staticTint(for condition: WeatherCondition) -> some View {
        switch condition {
        case .clear:
            Color.orange.opacity(0.01)
        case .overcast:
            Color.gray.opacity(0.02)
        case .lightRain:
            Color(white: 0.55).opacity(0.01)
        case .heavyRain:
            Color(white: 0.4).opacity(0.02)
        case .thunderstorm:
            Color.black.opacity(0.03)
        case .fog:
            RadialGradient(
                colors: [Color.white.opacity(0.04), Color.white.opacity(0.01)],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
        case .haze:
            Color.brown.opacity(0.02)
        case .partlyCloudy, .snow, .wind:
            Color.clear
        }
    }

    // MARK: - Particle Layers

    @ViewBuilder
    private func particleLayer(for condition: WeatherCondition) -> some View {
        switch condition {
        case .partlyCloudy:
            CloudDriftCanvas()
        case .lightRain:
            RainCanvas(particleCount: 20, opacity: 0.03)
        case .heavyRain:
            RainCanvas(particleCount: 40, opacity: 0.03)
        case .thunderstorm:
            LightningFlashView()
        case .snow:
            SnowCanvas()
        case .wind:
            WindStreakCanvas()
        case .clear, .overcast, .fog, .haze:
            EmptyView()
        }
    }
}

// MARK: - Cloud Drift (partlyCloudy)

private struct CloudDriftCanvas: View {

    private struct Cloud {
        var x: Double
        let y: Double
        let width: Double
        let height: Double
        let speed: Double
        let opacity: Double
    }

    private static func makeClouds() -> [Cloud] {
        [
            Cloud(x: 0.05, y: 0.15, width: 180, height: 50, speed: 0.0003, opacity: 0.03),
            Cloud(x: 0.40, y: 0.35, width: 220, height: 60, speed: 0.0004, opacity: 0.04),
            Cloud(x: 0.75, y: 0.55, width: 260, height: 70, speed: 0.0005, opacity: 0.05),
        ]
    }

    private let clouds = makeClouds()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 10)) { timeline in
            Canvas { context, size in
                let now: Double = timeline.date.timeIntervalSinceReferenceDate
                for cloud in clouds {
                    let divisor: Double = size.width + cloud.width
                    let xOffset: Double = (now * cloud.speed * size.width)
                        .truncatingRemainder(dividingBy: divisor)
                    let drawX: Double = xOffset - cloud.width * 0.5
                    let drawY: Double = cloud.y * size.height
                    let rect = CGRect(x: drawX, y: drawY, width: cloud.width, height: cloud.height)
                    context.opacity = cloud.opacity
                    context.fill(
                        Ellipse().path(in: rect),
                        with: .color(.fog)
                    )
                }
            }
        }
    }
}

// MARK: - Rain (lightRain / heavyRain)

private struct RainCanvas: View {

    let particleCount: Int
    let opacity: Double

    private struct Drop {
        var y: Double
        let x: Double
        let length: Double
        let speed: Double
    }

    @State private var drops: [Drop] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for drop in drops {
                    let progress = (now * drop.speed).truncatingRemainder(dividingBy: 1.2)
                    let yPos = progress * size.height
                    let xPos = drop.x * size.width + progress * 12

                    var path = Path()
                    path.move(to: CGPoint(x: xPos, y: yPos))
                    path.addLine(to: CGPoint(x: xPos + 2, y: yPos + drop.length))

                    context.stroke(
                        path,
                        with: .color(.ink.opacity(opacity)),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .onAppear { seedDrops() }
    }

    private func seedDrops() {
        drops = (0..<particleCount).map { _ in
            Drop(
                y: Double.random(in: 0...1),
                x: Double.random(in: 0...1),
                length: Double.random(in: 12...22),
                speed: Double.random(in: 0.35...0.6)
            )
        }
    }
}

// MARK: - Lightning Flash (thunderstorm)

private struct LightningFlashView: View {

    @State private var flashOpacity: Double = 0
    @State private var generation = 0

    var body: some View {
        Color.white.opacity(flashOpacity)
            .onAppear {
                generation += 1
                runFlashCycle(generation: generation)
            }
            .onDisappear {
                generation += 1
                flashOpacity = 0
            }
    }

    private func runFlashCycle(generation gen: Int) {
        let delay = Double.random(in: 10...14)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == gen else { return }
            withAnimation(.easeIn(duration: 0.05)) { flashOpacity = 0.06 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard generation == gen else { return }
                withAnimation(.easeOut(duration: 0.05)) { flashOpacity = 0 }
                runFlashCycle(generation: gen)
            }
        }
    }
}

// MARK: - Snow

private struct SnowCanvas: View {

    private struct Flake {
        let x: Double
        let speed: Double
        let drift: Double
        let phase: Double
    }

    @State private var flakes: [Flake] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for flake in flakes {
                    let progress = (now * flake.speed + flake.phase)
                        .truncatingRemainder(dividingBy: 1.3)
                    let yPos = progress * size.height
                    let sineOffset = sin(now * flake.drift) * 15
                    let xPos = flake.x * size.width + sineOffset

                    let rect = CGRect(x: xPos - 2, y: yPos - 2, width: 4, height: 4)
                    context.opacity = 0.04
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(.white)
                    )
                }
            }
        }
        .onAppear { seedFlakes() }
    }

    private func seedFlakes() {
        flakes = (0..<25).map { _ in
            Flake(
                x: Double.random(in: 0...1),
                speed: Double.random(in: 0.12...0.25),
                drift: Double.random(in: 0.4...1.0),
                phase: Double.random(in: 0...1.3)
            )
        }
    }
}

// MARK: - Wind Streaks

private struct WindStreakCanvas: View {

    private struct Streak {
        let y: Double
        let speed: Double
        let length: Double
        let phase: Double
    }

    @State private var streaks: [Streak] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for streak in streaks {
                    let progress = ((now * streak.speed + streak.phase)
                        .truncatingRemainder(dividingBy: 1.4))
                    let xPos = progress * (size.width + streak.length) - streak.length
                    let yPos = streak.y * size.height

                    var path = Path()
                    path.move(to: CGPoint(x: xPos, y: yPos))
                    path.addLine(to: CGPoint(x: xPos + streak.length, y: yPos - 3))

                    context.stroke(
                        path,
                        with: .color(.fog.opacity(0.03)),
                        lineWidth: 0.6
                    )
                }
            }
        }
        .onAppear { seedStreaks() }
    }

    private func seedStreaks() {
        streaks = (0..<12).map { _ in
            Streak(
                y: Double.random(in: 0.05...0.95),
                speed: Double.random(in: 0.5...0.9),
                length: Double.random(in: 40...80),
                phase: Double.random(in: 0...1.4)
            )
        }
    }
}
