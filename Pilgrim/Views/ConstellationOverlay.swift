import SwiftUI

struct ConstellationOverlay: View {

    static let staticOpacity: Double = 0.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var stars: [Star] = []
    @State private var shooting: ShootingState = .idle

    var body: some View {
        GeometryReader { geo in
            content(canvasSize: geo.size)
                .onAppear {
                    if stars.isEmpty {
                        stars = Self.generateStars(canvasSize: geo.size)
                    }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(canvasSize: CGSize) -> some View {
        if reduceTransparency {
            EmptyView()
        } else if reduceMotion {
            staticView(canvasSize: canvasSize)
        } else {
            animatedView(canvasSize: canvasSize)
        }
    }

    private func staticView(canvasSize: CGSize) -> some View {
        Canvas { gc, size in
            for star in stars {
                drawStar(gc: gc, star: star, size: size, opacity: Self.staticOpacity)
            }
        }
    }

    private func animatedView(canvasSize: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { ctx in
            Canvas { gc, size in
                let now = ctx.date
                let t = now.timeIntervalSinceReferenceDate

                for star in stars {
                    let phase = sin(t * 2 * .pi * star.twinkleFrequencyHz + star.twinklePhaseRadians)
                    let opacity = star.baseOpacity * (0.5 + 0.5 * phase)
                    drawStar(gc: gc, star: star, size: size, opacity: opacity)
                }

                if case .active(let start, let line) = shooting {
                    let elapsed = now.timeIntervalSince(start)
                    if elapsed < 0.6 {
                        drawShootingStar(gc: gc, line: line, elapsed: elapsed, size: size)
                    }
                    // No state mutation here — the .task driver below schedules transitions.
                }
            }
        }
        .task {
            // Drives shooting-star scheduling outside the Canvas render path.
            // Cancelled automatically when the view leaves the hierarchy.
            while !Task.isCancelled {
                let waitSeconds = Double.random(in: 30...90)
                do {
                    try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                } catch { return }
                guard !Task.isCancelled else { return }

                let line = Self.randomShootingLine(in: canvasSize)
                await MainActor.run { shooting = .active(start: Date(), line: line) }

                do {
                    try await Task.sleep(nanoseconds: 600_000_000)  // 600 ms shooting duration
                } catch { return }
                guard !Task.isCancelled else { return }

                await MainActor.run { shooting = .idle }
            }
        }
    }

    private func drawStar(gc: GraphicsContext, star: Star, size: CGSize, opacity: Double) {
        let x = star.position.x * size.width
        let y = star.position.y * size.height
        let tint = star.tint
        let baseColor = Color(red: tint.r, green: tint.g, blue: tint.b)

        // Soft outer halo — large, dim, single-color fill so it reads as glow.
        let haloRadius = star.radius * 3.5
        let haloRect = CGRect(
            x: x - haloRadius,
            y: y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        )
        gc.fill(
            Path(ellipseIn: haloRect),
            with: .color(baseColor.opacity(opacity * 0.18))
        )

        // Mid ring — pulls the eye toward the bright core.
        let midRadius = star.radius * 1.8
        let midRect = CGRect(
            x: x - midRadius,
            y: y - midRadius,
            width: midRadius * 2,
            height: midRadius * 2
        )
        gc.fill(
            Path(ellipseIn: midRect),
            with: .color(baseColor.opacity(opacity * 0.45))
        )

        // Bright core — sharp, near-white pinpoint.
        let coreRect = CGRect(
            x: x - star.radius,
            y: y - star.radius,
            width: star.radius * 2,
            height: star.radius * 2
        )
        gc.fill(
            Path(ellipseIn: coreRect),
            with: .color(baseColor.opacity(opacity))
        )
    }

    private func drawShootingStar(gc: GraphicsContext, line: ShootingLine, elapsed: Double, size: CGSize) {
        let progress = elapsed / 0.6
        let alpha = sin(.pi * progress) // smooth fade in + out
        let head = CGPoint(
            x: line.start.x + (line.end.x - line.start.x) * progress,
            y: line.start.y + (line.end.y - line.start.y) * progress
        )
        let tail = CGPoint(
            x: line.start.x + (line.end.x - line.start.x) * max(0, progress - 0.15),
            y: line.start.y + (line.end.y - line.start.y) * max(0, progress - 0.15)
        )
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        gc.stroke(
            path,
            with: .color(.white.opacity(alpha * 0.9)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )
    }

    static func generateStars(canvasSize: CGSize) -> [Star] {
        let count = Int.random(in: 5...14)
        return (0..<count).map { _ in
            let layer = Star.Layer.allCases.randomElement()!
            let useWarm = Double.random(in: 0...1) < 0.3
            return Star(
                position: CGPoint(x: CGFloat.random(in: 0.05...0.95), y: CGFloat.random(in: 0.05...0.95)),
                layer: layer,
                radius: layer.radius,
                baseOpacity: 0.6 + Double.random(in: 0...0.35),
                twinkleFrequencyHz: Double.random(in: 0.2...0.4),
                twinklePhaseRadians: Double.random(in: 0...(2 * .pi)),
                tint: useWarm ? .warm : .cool
            )
        }
    }

    static func randomShootingLine(in size: CGSize) -> ShootingLine {
        // Pick start corner randomly so streaks don't always travel
        // down-right; angle is constrained to ~25-45° from horizontal
        // for a "falling" look.
        let fromLeft = Bool.random()
        let startY = CGFloat.random(in: 0...size.height * 0.4)
        let startX = fromLeft
            ? CGFloat.random(in: 0...size.width * 0.3)
            : CGFloat.random(in: size.width * 0.7...size.width)
        let length = size.width * CGFloat.random(in: 0.4...0.6)
        let absAngle = CGFloat.random(in: 0.43...0.79)  // 25°–45° in radians
        let dx = (fromLeft ? 1 : -1) * length * cos(absAngle)
        let dy = length * sin(absAngle)
        return ShootingLine(
            start: CGPoint(x: startX, y: startY),
            end: CGPoint(x: startX + dx, y: startY + dy)
        )
    }
}

struct Star {
    let position: CGPoint        // normalized 0..1
    let layer: Layer
    let radius: CGFloat
    let baseOpacity: Double
    let twinkleFrequencyHz: Double
    let twinklePhaseRadians: Double
    let tint: Tint

    enum Layer: CaseIterable {
        case far, mid, near
        var radius: CGFloat {
            switch self {
            case .far:  return 1.2
            case .mid:  return 1.8
            case .near: return 2.6
            }
        }
    }

    struct Tint {
        let r: Double
        let g: Double
        let b: Double
        static let cool = Tint(r: 232.0/255, g: 224.0/255, b: 255.0/255)
        static let warm = Tint(r: 255.0/255, g: 232.0/255, b: 220.0/255)
    }
}

struct ShootingLine {
    let start: CGPoint
    let end: CGPoint
}

enum ShootingState {
    case idle
    case active(start: Date, line: ShootingLine)
}
