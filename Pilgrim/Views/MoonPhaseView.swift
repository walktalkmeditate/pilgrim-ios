import SwiftUI

struct MoonPhaseView: View {

    let phase: LunarPhase
    var size: CGFloat = 44

    @State private var glowPulse: CGFloat = 1.0
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isDark
                                ? [Color.ink.opacity(0.06), Color.clear]
                                : [Color.stone.opacity(0.12), Color.stone.opacity(0.02), Color.clear],
                            center: .center,
                            startRadius: size * 0.2,
                            endRadius: size * 1.2 * glowPulse
                        )
                    )
                    .frame(width: size * 2.5, height: size * 2.5)

                if !isDark {
                    MoonPhaseShape(illumination: phase.illumination, isWaxing: phase.isWaxing)
                        .fill(Color.stone.opacity(0.08))
                        .frame(width: size + 4, height: size + 4)
                        .blur(radius: 3)
                }

                MoonPhaseShape(illumination: phase.illumination, isWaxing: phase.isWaxing)
                    .fill(isDark ? Color.ink.opacity(0.35) : Color.stone.opacity(0.4))
                    .frame(width: size, height: size)
                    .shadow(
                        color: isDark ? .clear : Color.stone.opacity(0.15),
                        radius: 6, x: 0, y: 2
                    )
            }
            .accessibilityLabel(phase.name)
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    glowPulse = 1.08
                }
            }

            Text(phase.name)
                .font(Constants.Typography.annotation)
                .foregroundColor(.fog)
        }
    }
}

struct MoonPhaseShape: Shape {

    let illumination: Double
    let isWaxing: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()
        path.addArc(center: center, radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: isWaxing)

        let fraction = abs(2 * illumination - 1)
        let curveRadius = r * fraction
        let controlOffset = curveRadius * (4.0 / 3.0)
        let litHalf = illumination > 0.5

        let top = CGPoint(x: center.x, y: center.y - r)

        let curveGoesRight = (isWaxing && litHalf) || (!isWaxing && !litHalf)
        let sign: CGFloat = curveGoesRight ? 1 : -1

        path.addCurve(
            to: top,
            control1: CGPoint(x: center.x + sign * controlOffset, y: center.y + r * 0.55),
            control2: CGPoint(x: center.x + sign * controlOffset, y: center.y - r * 0.55)
        )

        return path
    }
}
