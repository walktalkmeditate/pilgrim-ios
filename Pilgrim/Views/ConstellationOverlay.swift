import Combine
import SwiftUI

struct ConstellationOverlay: View {

    static let staticOpacity: Double = 0.6

    let includesNebulae: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var stars: [Star]
    @State private var nebulae: [Nebula]
    @State private var shooting: ShootingState = .idle
    /// Low Power Mode drops the timeline cadence to 10 fps. Normal mode
    /// stays at the 60 fps documented in PR #40's architecture notes —
    /// the gate exists so a multi-hour walk on a dying battery isn't
    /// spending it on star twinkle. `isLowPowerModeEnabled` is not
    /// KVO/Combine-observable directly, so we track it via the
    /// processInfoPowerStateDidChange notification (which can arrive
    /// off-main).
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    init(includesNebulae: Bool = true) {
        // Populate at view-init time. Star positions are normalized 0..1
        // so the canvas-size hint here doesn't affect placement once they
        // render. Nebula radii are absolute points and use a screen-ish
        // hint. .onAppear was unreliable for triggering this — state
        // mutations from there didn't always propagate to the Canvas
        // before some later body re-eval (e.g. shooting-star ~30s in).
        self.includesNebulae = includesNebulae
        let hint = CGSize(width: 393, height: 852)
        _stars = State(initialValue: Self.generateStars(canvasSize: hint))
        _nebulae = State(
            initialValue: includesNebulae ? Self.generateNebulae(canvasSize: hint) : []
        )
    }

    var body: some View {
        GeometryReader { geo in
            content(canvasSize: geo.size)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(
            NotificationCenter.default
                .publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
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
            drawCosmicGradient(gc: gc, size: size)
            for nebula in nebulae {
                drawNebula(gc: gc, nebula: nebula, size: size, time: 0)
            }
            for star in stars {
                let pos = staticPosition(for: star, size: size)
                drawStar(gc: gc, position: pos, radius: star.radius, tint: star.tint, opacity: Self.staticOpacity)
            }
        }
    }

    private func animatedView(canvasSize: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: isLowPower ? 1.0 / 10.0 : 1.0 / 60.0)) { ctx in
            Canvas { gc, size in
                let now = ctx.date
                let t = now.timeIntervalSinceReferenceDate

                drawCosmicGradient(gc: gc, size: size)

                for nebula in nebulae {
                    drawNebula(gc: gc, nebula: nebula, size: size, time: t)
                }

                for star in stars {
                    let phase = sin(t * 2 * .pi * star.twinkleFrequencyHz + star.twinklePhaseRadians)
                    let opacity = star.baseOpacity * (0.5 + 0.5 * phase)
                    let pos = driftedPosition(for: star, time: t, size: size)
                    drawStar(gc: gc, position: pos, radius: star.radius, tint: star.tint, opacity: opacity)
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

    private func drawStar(gc: GraphicsContext, position: CGPoint, radius: CGFloat, tint: Star.Tint, opacity: Double) {
        let x = position.x
        let y = position.y
        let baseColor = Color(red: tint.r, green: tint.g, blue: tint.b)

        // Soft outer halo — large, dim, single-color fill so it reads as glow.
        let haloRadius = radius * 3.5
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
        let midRadius = radius * 1.8
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
            x: x - radius,
            y: y - radius,
            width: radius * 2,
            height: radius * 2
        )
        gc.fill(
            Path(ellipseIn: coreRect),
            with: .color(baseColor.opacity(opacity))
        )
    }

    private func staticPosition(for star: Star, size: CGSize) -> CGPoint {
        CGPoint(x: star.position.x * size.width, y: star.position.y * size.height)
    }

    private func driftedPosition(for star: Star, time: TimeInterval, size: CGSize) -> CGPoint {
        // Layer-keyed drift speed in points-per-second.
        // Far layer drifts slowest; near layer drifts fastest — depth illusion.
        // Vertical sway is a tiny sin oscillation per-star so the field feels
        // alive without any star traveling far from its anchor.
        let speed: CGFloat
        switch star.layer {
        case .far:  speed = 0.4
        case .mid:  speed = 0.9
        case .near: speed = 1.6
        }

        let basePixelX = star.position.x * size.width
        let driftX = CGFloat(time) * speed
        let cycle = size.width + 80  // wrap range — extends past edges so wraps aren't visible
        var wrappedX = (basePixelX + driftX).truncatingRemainder(dividingBy: cycle)
        if wrappedX < 0 { wrappedX += cycle }

        let basePixelY = star.position.y * size.height
        // Subtle vertical sway. Amplitude scales with depth layer (near layer
        // sways most). Period derived deterministically from the star's
        // twinkle phase so each star sways at a stable cadence.
        let swayAmplitude: CGFloat = (star.layer == .near) ? 10 : (star.layer == .mid ? 6 : 4)
        let swayPeriodSeconds: Double = 30.0 + (star.twinklePhaseRadians / (2 * .pi)) * 30.0
        let swayHz = 1.0 / swayPeriodSeconds
        let pixelY = basePixelY + swayAmplitude * CGFloat(sin(time * 2 * .pi * swayHz + star.twinklePhaseRadians))

        return CGPoint(x: wrappedX, y: pixelY)
    }

    private func drawCosmicGradient(gc: GraphicsContext, size: CGSize) {
        // Slightly brighter center fading to flat indigo at the edges.
        // Adds cosmic depth beneath the flat #0a0a12 canvasBackground.
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(size.width, size.height) * 0.7
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let centerTint = Color(red: 0.10, green: 0.10, blue: 0.16)
        let gradient = Gradient(stops: [
            .init(color: centerTint.opacity(0.55), location: 0.0),
            .init(color: centerTint.opacity(0.18), location: 0.5),
            .init(color: Color.clear, location: 1.0)
        ])
        let shading = GraphicsContext.Shading.radialGradient(
            gradient,
            center: center,
            startRadius: 0,
            endRadius: radius
        )
        gc.fill(Path(rect), with: shading)
    }

    private func drawNebula(gc: GraphicsContext, nebula: Nebula, size: CGSize, time: TimeInterval) {
        let baseX = nebula.basePosition.x * size.width
        let baseY = nebula.basePosition.y * size.height
        let driftX = CGFloat(time) * nebula.driftSpeed
        // Wrap range covers off-screen on both sides so the soft halo
        // never abruptly snaps back to start. At t=0, the nebula renders
        // at its base position.
        let cycle = size.width + nebula.radius * 2
        let shifted = baseX + driftX + nebula.radius
        var modded = shifted.truncatingRemainder(dividingBy: cycle)
        if modded < 0 { modded += cycle }
        let centerX = modded - nebula.radius

        let rect = CGRect(
            x: centerX - nebula.radius,
            y: baseY - nebula.radius,
            width: nebula.radius * 2,
            height: nebula.radius * 2
        )
        let tint = nebula.tint
        let color = Color(red: tint.r, green: tint.g, blue: tint.b)
        let gradient = Gradient(stops: [
            .init(color: color.opacity(0.32), location: 0.0),
            .init(color: color.opacity(0.16), location: 0.35),
            .init(color: color.opacity(0.06), location: 0.7),
            .init(color: Color.clear, location: 1.0)
        ])
        let shading = GraphicsContext.Shading.radialGradient(
            gradient,
            center: CGPoint(x: centerX, y: baseY),
            startRadius: 0,
            endRadius: nebula.radius
        )
        gc.fill(Path(ellipseIn: rect), with: shading)
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

struct Nebula {
    let basePosition: CGPoint   // 0..1 normalized
    let radius: CGFloat         // points
    let tint: Tint
    let driftSpeed: CGFloat     // pt/sec — very slow

    struct Tint {
        let r: Double
        let g: Double
        let b: Double
        // Lighter, more saturated picks — at 0.32 max opacity these read
        // as soft purple/blue mist against the #0a0a12 indigo canvas.
        static let violet = Tint(r: 0.62, g: 0.42, b: 0.92)
        static let indigo = Tint(r: 0.40, g: 0.52, b: 0.92)
        static let plum   = Tint(r: 0.78, g: 0.52, b: 0.82)
    }
}

extension ConstellationOverlay {
    static func generateNebulae(canvasSize: CGSize) -> [Nebula] {
        // 2-3 large soft blotches at gentle parallax-style drift speeds.
        // Larger radii (260-340pt) make the gradient soft enough that the
        // brighter tints don't read as solid blobs — instead they feel
        // like distant cosmic clouds. Positions chosen to spread across
        // the canvas without overlap.
        let candidates: [Nebula] = [
            Nebula(basePosition: CGPoint(x: 0.25, y: 0.20), radius: 280, tint: .violet, driftSpeed: 0.6),
            Nebula(basePosition: CGPoint(x: 0.75, y: 0.55), radius: 340, tint: .indigo, driftSpeed: 0.4),
            Nebula(basePosition: CGPoint(x: 0.45, y: 0.85), radius: 260, tint: .plum, driftSpeed: 0.8)
        ]
        return Array(candidates.shuffled().prefix(Int.random(in: 2...3)))
    }
}
