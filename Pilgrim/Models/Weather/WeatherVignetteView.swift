import SwiftUI

struct WeatherVignetteView: View {

    let snapshot: WeatherSnapshot?
    let imperial: Bool

    @State private var expanded = false

    var body: some View {
        if let snapshot {
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { expanded.toggle() } } label: {
                content(for: snapshot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Weather: \(snapshot.condition.label), \(snapshot.formattedTemperature(imperial: imperial))")
            .accessibilityHint("Double tap to expand weather details")
        }
    }

    private func content(for snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.condition.icon)
                .font(.caption2)

            Text(snapshot.formattedTemperature(imperial: imperial))
                .font(Constants.Typography.caption)

            if expanded {
                Text("\(Int(snapshot.humidity * 100))%")
                    .font(Constants.Typography.caption)

                Text(snapshot.windDescription)
                    .font(Constants.Typography.caption)
            }
        }
        .foregroundColor(.fog)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

}
