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
                if isDark {
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
                } else {
                    let silver = Color(red: 0.55, green: 0.58, blue: 0.65)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [silver.opacity(0.18), silver.opacity(0.06), Color.clear],
                                center: .center,
                                startRadius: size * 0.15,
                                endRadius: size * 1.4 * glowPulse
                            )
                        )
                        .frame(width: size * 3, height: size * 3)

                    MoonPhaseShape(illumination: phase.illumination, isWaxing: phase.isWaxing)
                        .fill(silver.opacity(0.15))
                        .frame(width: size + 6, height: size + 6)
                        .blur(radius: 4)

                    MoonPhaseShape(illumination: phase.illumination, isWaxing: phase.isWaxing)
                        .fill(
                            LinearGradient(
                                colors: [silver.opacity(0.5), Color.fog.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size, height: size)
                        .shadow(color: silver.opacity(0.25), radius: 8, x: 0, y: 0)
                }
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

        if illumination > 0.95 {
            var full = Path()
            full.addArc(center: center, radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            return full
        }

        if illumination < 0.05 {
            return Path()
        }

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
