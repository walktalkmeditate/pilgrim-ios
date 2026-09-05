import CoreLocation
import Network
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
        // Int(_:) traps on an out-of-range Double AND on a NaN or infinity,
        // which no clamp catches; a Way from any source stays safe.
        if let t = theirs.temperatureC, t.isFinite { line += " at \(Int(min(max(t.rounded(), -1000), 1000)))°" }
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

    /// Offline tiles are slice three. Until then a stage walked without a
    /// connection draws over the basemap's empty grey, and the overview says
    /// so once — the ghost line, the pins, the marks, the cards, the water,
    /// and the ledger all work without a network.
    static func offlineNote(isStage: Bool, isConnected: Bool, alreadyShown: Bool) -> String? {
        guard isStage, !isConnected, !alreadyShown else { return nil }
        return "map tiles need a connection; the way itself is on your phone."
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
    let importState: HonorImportState
    let onBegin: () -> Void
    let onClose: () -> Void
    let onRetryMedia: () -> Void
    let onWalkWithoutMissing: () -> Void

    /// Where the map's camera actually is, as the map reports it. Nil until
    /// the first report: this screen opens fit to the whole Way, a zoom it
    /// never chose and cannot know, and marks must not be drawn on a guess.
    @State private var liveCenter: CLLocationCoordinate2D?
    @State private var liveZoom: CGFloat?
    @State private var isMeditating = false
    @State private var distanceToStart: Double?
    @State private var todayCondition: String?
    @State private var voicesEnabled = UserPreferences.honorVoicesEnabled.value
    @State private var showMorningCard = false
    @State private var todayWeather: WeatherSnapshot?
    @State private var isConnected = true
    @State private var offlineNote: String?
    #if DEBUG
    @State private var debugExportURL: URL?
    @State private var isShowingDebugExport = false
    #endif

    /// The three O(route) derivations the map needs. `importState` changes on
    /// every gathering tick and re-runs `body`, so these are computed once per
    /// Way in `.task(id:)` rather than three times per tick.
    private struct WayRendering {
        let pins: [PilgrimAnnotation]
        let bounds: MapCameraBounds?
        let state: HonorWayState
    }

    @State private var rendering: WayRendering?
    /// The stage's service pins. Not part of `WayRendering`: they answer to
    /// the live camera the map reports, not to the Way alone — fit to a whole
    /// stage they are all below `WayMarkPins.drawFromZoom` and none is drawn.
    @State private var markPins: [PilgrimAnnotation] = []
    /// A tapped pin: its photo or voice in a half-height sheet of its own.
    @State private var previewMoment: WayMoment?

    var body: some View {
        VStack(spacing: 0) {
            PilgrimMapView(
                isInteractive: true,
                showsUserLocation: true,
                followsUserLocation: false,
                pinAnnotations: markPins + (rendering?.pins ?? []),
                onAnnotationTap: { pin in
                    guard let id = pin.kind.wayMomentID else { return }
                    previewMoment = way.moments.first { $0.id == id }
                },
                cameraBounds: rendering?.bounds,
                isMeditating: $isMeditating,
                honorWay: rendering?.state,
                onCameraChanged: { center, zoom in
                    liveCenter = center
                    liveZoom = zoom
                    refreshMarkPins()
                }
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
            #if DEBUG
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Export simulation GPX", action: exportSimulationGPX)
                } label: {
                    Image(systemName: "ladybug")
                }
            }
            #endif
        }
        .onAppear { probeDistance(); checkConnectivity() }
        .task(id: way.id) {
            rendering = WayRendering(
                pins: PilgrimMapView.wayPins(for: way, heardVoiceIDs: []),
                bounds: HonorOverviewModel.bounds(of: way),
                state: HonorWayState(way: way)
            )
            refreshMarkPins()
        }
        .task { await fetchToday() }
        .sheet(item: $previewMoment) { moment in
            WayMomentPreview(
                way: way,
                moment: moment,
                mediaURL: moment.media.flatMap { ActiveWalkViewModel.localMediaURL(for: $0, wayId: way.id, store: WayStore.shared) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMorningCard) {
            if let stage = way.stage {
                StageMorningCard(stage: stage, weather: todayWeather, buttonTitle: "walk") {
                    showMorningCard = false
                    onBegin()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        #if DEBUG
        .sheet(isPresented: $isShowingDebugExport) {
            if let debugExportURL {
                ShareSheet(items: [debugExportURL])
            }
        }
        #endif
    }

    #if DEBUG
    /// Xcode's Core Location simulation only reads `<wpt>` elements, so this
    /// hands the file to the share sheet for an AirDrop to the developer's Mac
    /// — see docs/honor-simulation.md.
    private func exportSimulationGPX() {
        let data = WayGPXExporter.gpx(for: way)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(way.id.replacingOccurrences(of: ":", with: "-")).gpx")
        do {
            try data.write(to: url)
            debugExportURL = url
            isShowingDebugExport = true
        } catch {
            print("[HonorOverviewView] Failed to export simulation GPX: \(error)")
        }
    }
    #endif

    private var card: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text(way.title)
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            Text(WayStageLine.line(for: way)
                 ?? DateFormatter.localizedString(from: way.departedAt, dateStyle: .long, timeStyle: .short))
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
            importLine
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
            if let offlineNote {
                Text(offlineNote)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            // A stage carries no recordings, so "walk with their voice" would
            // be a switch over nothing — and would say "their" besides.
            if !way.isPilgrimageStage {
                Toggle(isOn: $voicesEnabled) {
                    Text("walk with their voice")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                }
                .tint(.stone)
                .onChange(of: voicesEnabled) { _, on in UserPreferences.honorVoicesEnabled.value = on }
                .disabled(way.voiceCount == 0)
            }

            Button {
                if way.isPilgrimageStage { showMorningCard = true } else { onBegin() }
            } label: {
                Text("Begin")
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isGathering ? Color.fog : Color.stone)
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .accessibilityLabel(way.isPilgrimageStage ? "Walk this stage" : "Begin honoring this way")
            .disabled(isGathering)
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchment)
    }

    /// `.fetching` too, not only `.gathering`: a link tapped for a different
    /// Way while this overview is up can still swap the sheet out from under
    /// a Begin tap, so Begin stays disabled for the whole window a fetch or a
    /// download could still land.
    private var isGathering: Bool {
        switch importState {
        case .gathering, .fetching: return true
        default: return false
        }
    }

    private var isTrouble: Bool {
        switch importState {
        case .failed, .mediaMissing: return true
        default: return false
        }
    }

    /// The one place the import speaks on this screen: its line under the
    /// counts, and — only when files are actually missing — the choice
    /// between waiting for them and walking without them.
    @ViewBuilder
    private var importLine: some View {
        if let line = HonorImportCopy.line(for: importState) {
            Text(line)
                .font(Constants.Typography.caption)
                .foregroundColor(isTrouble ? .rust : .fog)
        }
        if case .mediaMissing = importState {
            // Vertical, not the section's usual horizontal pairing: the
            // second label is long enough to clip on an SE width at large
            // accessibility type sizes if it has to share a row.
            VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                Button("try again", action: onRetryMedia)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                Button("walk without the missing voices", action: onWalkWithoutMissing)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .font(Constants.Typography.caption)
            .foregroundColor(.stone)
        }
    }

    /// "Today is clear": the same service the walk uses, on the walker's
    /// current fix; silent when offline or without a fix.
    private func fetchToday() async {
        guard let here = CLLocationManager().location,
              let snapshot = await WeatherService.shared.fetchCurrent(for: here) else { return }
        todayCondition = snapshot.condition.rawValue
        todayWeather = snapshot
    }

    private func durationText(_ seconds: Double) -> String {
        // Int(_:) traps on an out-of-range Double; clamp so a Way from any source stays safe.
        let clamped = Int(min(max(seconds, 0), 999_999_999))
        let hours = clamped / 3600, minutes = (clamped % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Nothing is drawn until the map has said where it is: a Way fit to a
    /// whole stage sits well below the draw-from zoom, and the first forty
    /// marks in file order would clump at one end of it.
    private func refreshMarkPins() {
        guard let zoom = liveZoom else {
            markPins = []
            return
        }
        markPins = WayMarkPins.pins(marks: way.marks ?? [], zoom: zoom, near: liveCenter)
    }

    private func probeDistance() {
        guard let first = way.route.first, let here = CLLocationManager().location else { return }
        distanceToStart = here.distance(from: CLLocation(latitude: first.lat, longitude: first.lon))
    }

    /// A single probe, cancelled in its own handler — no monitor outlives
    /// this screen.
    private func checkConnectivity() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                isConnected = connected
                if let note = HonorOverviewModel.offlineNote(
                    isStage: way.isPilgrimageStage, isConnected: connected,
                    alreadyShown: UserPreferences.pilgrimageOfflineNoteShown.value) {
                    offlineNote = note
                    UserPreferences.pilgrimageOfflineNoteShown.value = true
                }
            }
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue(label: "honor-connectivity-check"))
    }
}
