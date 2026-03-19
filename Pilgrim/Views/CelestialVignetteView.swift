import SwiftUI

struct CelestialVignetteView: View {

    let snapshot: CelestialSnapshot

    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { expanded.toggle() } } label: {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double tap to expand celestial details")
    }

    private var content: some View {
        HStack(spacing: 4) {
            Text(snapshot.planetaryHour.planet.symbol)
                .font(Constants.Typography.caption)
            Text(moonSignGlyph)
                .font(Constants.Typography.caption)

            if expanded {
                Text(sunDescription)
                    .font(Constants.Typography.caption)
                Text(moonDescription)
                    .font(Constants.Typography.caption)
                Text("Hour of \(snapshot.planetaryHour.planet.name)")
                    .font(Constants.Typography.caption)
                if !snapshot.retrogradePlanets.isEmpty {
                    Text(retrogradeText)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                if let dominant = snapshot.elementBalance.dominant {
                    Text(dominant.rawValue.capitalized)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
        }
        .foregroundColor(.ink)
        .padding(.horizontal, Constants.UI.Padding.small)
        .padding(.vertical, Constants.UI.Padding.xs)
        .background(
            Capsule()
                .fill(Color.parchmentSecondary)
                .shadow(color: .ink.opacity(0.08), radius: 4, y: 2)
        )
    }

    private var moonSignGlyph: String {
        let pos = snapshot.system == .tropical
            ? snapshot.position(for: .moon)?.tropical
            : snapshot.position(for: .moon)?.sidereal
        return pos?.sign.symbol ?? ""
    }

    private var sunDescription: String {
        guard let pos = snapshot.position(for: .sun) else { return "" }
        let zodiac = snapshot.system == .tropical ? pos.tropical : pos.sidereal
        return "\(pos.planet.symbol) \(zodiac.sign.name) \(Int(zodiac.degree))\u{00B0}"
    }

    private var moonDescription: String {
        guard let pos = snapshot.position(for: .moon) else { return "" }
        let zodiac = snapshot.system == .tropical ? pos.tropical : pos.sidereal
        return "\(pos.planet.symbol) \(zodiac.sign.name) \(Int(zodiac.degree))\u{00B0}"
    }

    private var retrogradeText: String {
        snapshot.retrogradePlanets.map { "\($0.symbol)Rx" }.joined(separator: " ")
    }

    private var accessibilityText: String {
        var parts = [sunDescription, moonDescription, "Hour of \(snapshot.planetaryHour.planet.name)"]
        if !snapshot.retrogradePlanets.isEmpty {
            parts.append("\(snapshot.retrogradePlanets.map { $0.name }.joined(separator: ", ")) retrograde")
        }
        return parts.joined(separator: ", ")
    }
}
