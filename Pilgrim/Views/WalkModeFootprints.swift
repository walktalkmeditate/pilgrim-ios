import SwiftUI

/// Which mode's miniature a row wears.
enum WalkModeGlyph {
    case wander, honor, seek
}

/// Static miniature of the path screen's mode language, for compact rows
/// (the ink-scroll quick view). Wander: the grounded pair. Honor: one print
/// beside the staff of the walker whose Way is being followed. Seek: one
/// print beside a trail of dots dissolving upward into the unknown. No
/// animation — these are glances, not scenes; the drifting versions live on
/// the path screen only.
struct WalkModeFootprints: View {
    let mode: WalkModeGlyph
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            FootprintShape()
                .fill(color)
                .frame(width: 10, height: 16)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-12))
            switch mode {
            case .seek:
                dissolvingDots
                    .frame(width: 10, height: 18)
                    .rotationEffect(.degrees(12))
            case .honor:
                StaffGlyph()
                    .stroke(color, lineWidth: 1)
                    .frame(width: 8, height: 14)
            case .wander:
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
