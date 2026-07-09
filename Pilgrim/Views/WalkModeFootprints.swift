import SwiftUI

/// Static miniature of the path screen's mode language, for compact rows
/// (the ink-scroll quick view). Wander: the grounded pair. Seek: one print
/// beside a trail of dots dissolving upward into the unknown. No animation —
/// these are glances, not scenes; the drifting versions live on the path
/// screen only.
struct WalkModeFootprints: View {
    let isSeek: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            FootprintShape()
                .fill(color)
                .frame(width: 10, height: 16)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-12))
            if isSeek {
                dissolvingDots
                    .frame(width: 10, height: 18)
                    .rotationEffect(.degrees(12))
            } else {
                FootprintShape()
                    .fill(color.opacity(0.75))
                    .frame(width: 10, height: 16)
                    .rotationEffect(.degrees(12))
            }
        }
        .accessibilityHidden(true)
    }

    private var dissolvingDots: some View {
        Canvas { context, size in
            let dots: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] = [
                (0.5, 0.85, 1.6, 1.0),
                (0.3, 0.65, 1.3, 0.85),
                (0.7, 0.55, 1.3, 0.7),
                (0.4, 0.38, 1.0, 0.5),
                (0.6, 0.20, 1.0, 0.35),
                (0.5, 0.05, 0.7, 0.22)
            ]
            for dot in dots {
                let rect = CGRect(
                    x: dot.x * size.width - dot.r,
                    y: dot.y * size.height - dot.r,
                    width: dot.r * 2,
                    height: dot.r * 2
                )
                context.opacity = dot.a
                context.fill(Ellipse().path(in: rect), with: .color(color))
            }
        }
    }
}
