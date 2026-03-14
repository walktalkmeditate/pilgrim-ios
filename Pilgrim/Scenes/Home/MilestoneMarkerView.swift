import SwiftUI

struct MilestoneMarkerView: View {

    let width: CGFloat
    let distance: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.fog.opacity(0.15))
                    .frame(height: 0.5)

                ToriiGateShape()
                    .fill(Color.stone.opacity(0.25))
                    .frame(width: 16, height: 14)

                Text(distanceText)
                    .font(Constants.Typography.micro)
                    .foregroundColor(.fog.opacity(0.4))

                Rectangle()
                    .fill(Color.fog.opacity(0.15))
                    .frame(height: 0.5)
            }
            .frame(width: width * 0.7)
        }
        .accessibilityHidden(true)
    }

    private var distanceText: String {
        String(format: "%.0f km", distance / 1000)
    }
}
