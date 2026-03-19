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
            symbolText(snapshot.planetaryHour.planet.symbol)
            symbolText(moonSignGlyph)

            if expanded {
                symbolText(compactSummary)
                    .foregroundColor(.fog)
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

    private func symbolText(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 12))
    }

    private var moonSignGlyph: String {
        let pos = snapshot.system == .tropical
            ? snapshot.position(for: .moon)?.tropical
            : snapshot.position(for: .moon)?.sidereal
        return pos?.sign.symbol ?? ""
    }

    private var compactSummary: String {
        var parts: [String] = []

        if let sun = snapshot.position(for: .sun) {
            let z = snapshot.system == .tropical ? sun.tropical : sun.sidereal
            parts.append("\(sun.planet.symbol)\(z.sign.symbol)")
        }

        let retrogrades = snapshot.retrogradePlanets
        if !retrogrades.isEmpty {
            parts.append(retrogrades.map { "\($0.symbol)Rx" }.joined(separator: " "))
        }

        return parts.joined(separator: " ")
    }

    private var accessibilityText: String {
        var parts: [String] = []

        if let sun = snapshot.position(for: .sun) {
            let z = snapshot.system == .tropical ? sun.tropical : sun.sidereal
            parts.append("Sun in \(z.sign.name)")
        }
        if let moon = snapshot.position(for: .moon) {
            let z = snapshot.system == .tropical ? moon.tropical : moon.sidereal
            parts.append("Moon in \(z.sign.name)")
        }

        parts.append("Hour of \(snapshot.planetaryHour.planet.name)")

        if !snapshot.retrogradePlanets.isEmpty {
            parts.append("\(snapshot.retrogradePlanets.map { $0.name }.joined(separator: ", ")) retrograde")
        }

        return parts.joined(separator: ", ")
    }
}
