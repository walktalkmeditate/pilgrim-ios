import SwiftUI

struct MoonPhaseView: View {

    let phase: LunarPhase
    var size: CGFloat = 44

    @State private var glowPulse: CGFloat = 1.0

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ink.opacity(0.06), Color.clear],
                            center: .center,
                            startRadius: size * 0.3,
                            endRadius: size * 1.2 * glowPulse
                        )
                    )
                    .frame(width: size * 2.5, height: size * 2.5)

                MoonPhaseShape(illumination: phase.illumination, isWaxing: phase.isWaxing)
                    .fill(Color.ink.opacity(0.35))
                    .frame(width: size, height: size)
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
