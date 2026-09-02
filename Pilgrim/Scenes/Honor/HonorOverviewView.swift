import CoreLocation
import SwiftUI

enum HonorOverviewModel {

    static func countsLine(way: Way) -> String {
        var parts: [String] = []
        if way.voiceCount > 0 { parts.append(way.voiceCount == 1 ? "1 voice" : "\(way.voiceCount) voices") }
        if way.photoCount > 0 { parts.append(way.photoCount == 1 ? "1 photo" : "\(way.photoCount) photos") }
        return parts.isEmpty ? "a quiet way" : parts.joined(separator: " · ")
    }

    static func statusLine(distanceToStartMeters: Double?) -> String? {
        guard let meters = distanceToStartMeters else { return nil }
        if meters <= HonorTuning.onWayMeters { return "you're on the way" }
        let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        if imperial {
            let miles = meters / 1609.344
            return miles < 0.2 ? "\(Int(meters * 3.28084)) ft from the start"
                : String(format: "%.1f mi from the start", miles)
        }
        return meters < 1000 ? "\(Int(meters)) m from the start" : String(format: "%.1f km from the start", meters / 1000)
    }

    static func weatherLine(theirs: WayWeather?, today: String?) -> String? {
        guard let theirs else { return nil }
        var line = "they walked this in \(spoken(theirs.condition))"
        if let t = theirs.temperatureC { line += " at \(Int(t.rounded()))°" }
        line += "."
        if let today { line += " Today is \(spoken(today))." }
        return line
    }

    /// Conditions travel as `WeatherCondition` raw values ("lightRain"), which
    /// would otherwise reach the reader camel-cased. Strings from outside that
    /// vocabulary pass through untouched.
    private static func spoken(_ condition: String) -> String {
        WeatherCondition(rawValue: condition)?.label.lowercased() ?? condition
    }

    static func bounds(of way: Way) -> MapCameraBounds? {
        let lats = way.route.map(\.lat), lons = way.route.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return MapCameraBounds(sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                               ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon))
    }
}

/// The map fit to the whole Way, a card, and Begin. The camera never follows the puck here.
struct HonorOverviewView: View {

    let way: Way
    let onBegin: () -> Void
    let onClose: () -> Void

    @State private var cameraCenter: CLLocationCoordinate2D?
    @State private var cameraZoom: CGFloat = 14
    @State private var isMeditating = false
    @State private var distanceToStart: Double?
    @State private var todayCondition: String?
    @State private var voicesEnabled = UserPreferences.honorVoicesEnabled.value

    private var wayState: HonorWayState {
        HonorWayState(id: way.id,
                      routeCoordinates: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
    }

    var body: some View {
        VStack(spacing: 0) {
            PilgrimMapView(
                isInteractive: true,
                showsUserLocation: true,
                followsUserLocation: false,
                pinAnnotations: PilgrimMapView.wayPins(for: way, heardVoiceIDs: []),
                cameraCenter: $cameraCenter,
                cameraZoom: $cameraZoom,
                cameraBounds: HonorOverviewModel.bounds(of: way),
                isMeditating: $isMeditating,
                honorWay: wayState
            )
            .frame(maxHeight: .infinity)

            card
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
                    .font(Constants.Typography.button)
                    .foregroundColor(.stone)
            }
        }
        .onAppear { probeDistance() }
        .task { await fetchToday() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text(way.title)
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            Text(DateFormatter.localizedString(from: way.departedAt, dateStyle: .long, timeStyle: .short))
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            HStack {
                Text(StatsHelper.string(for: way.totalDistanceMeters, unit: UnitLength.meters, type: .distance))
                Text("·")
                Text(durationText(way.theirActiveSeconds))
                Text("·")
                Text(HonorOverviewModel.countsLine(way: way))
            }
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
            if let line = HonorOverviewModel.weatherLine(theirs: way.weather, today: todayCondition) {
                Text(line)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            if let status = HonorOverviewModel.statusLine(distanceToStartMeters: distanceToStart) {
                Text(status)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            Toggle(isOn: $voicesEnabled) {
                Text("walk with their voice")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
            }
            .tint(.stone)
            .onChange(of: voicesEnabled) { _, on in UserPreferences.honorVoicesEnabled.value = on }
            .disabled(way.voiceCount == 0)

            Button(action: onBegin) {
                Text("Begin")
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone)
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel("Begin honoring this way")
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchment)
    }

    /// "Today is clear": the same service the walk uses, on the walker's
    /// current fix; silent when offline or without a fix.
    private func fetchToday() async {
        guard let here = CLLocationManager().location,
              let snapshot = await WeatherService.shared.fetchCurrent(for: here) else { return }
        todayCondition = snapshot.condition.rawValue
    }

    private func durationText(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600, minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func probeDistance() {
        guard let first = way.route.first, let here = CLLocationManager().location else { return }
        distanceToStart = here.distance(from: CLLocation(latitude: first.lat, longitude: first.lon))
    }
}
