import SwiftUI
import CoreLocation

struct PromptListView: View {

    let walk: WalkInterface
    let transcriptions: [UUID: String]
    let recentWalkSnippets: [WalkSnippet]
    let intention: String?
    let photoCandidates: [PhotoCandidate]
    @State private var selectedPrompt: GeneratedPrompt?
    @State private var prompts: [GeneratedPrompt] = []
    @StateObject private var customStyleStore = CustomPromptStyleStore()
    @State private var showEditor = false
    @State private var editingStyle: CustomPromptStyle?
    @State private var activityContext: ActivityContext?
    @State private var customPrompts: [GeneratedPrompt] = []

    var body: some View {
        List {
            Section {
                ForEach(prompts) { prompt in
                    Button { selectedPrompt = prompt } label: {
                        PromptStyleRow(prompt: prompt)
                    }
                    .listRowBackground(Color.parchment)
                }
            }

            if !customStyleStore.styles.isEmpty {
                Section {
                    ForEach(customPrompts) { prompt in
                        Button { selectedPrompt = prompt } label: {
                            PromptStyleRow(prompt: prompt)
                        }
                        .listRowBackground(Color.parchment)
                        .swipeActions(edge: .leading) {
                            if let customStyle = prompt.customStyle {
                                Button {
                                    editingStyle = customStyle
                                    showEditor = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.stone)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if let customStyle = customPrompts[index].customStyle {
                                customStyleStore.delete(customStyle)
                            }
                        }
                        regenerateCustomPrompts()
                    }
                }
            }

            Section {
                createYourOwnRow
                    .listRowBackground(Color.parchment)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationTitle("AI Prompts")
        .sheet(item: $selectedPrompt) { prompt in
            PromptDetailView(prompt: prompt)
        }
        .sheet(isPresented: $showEditor) {
            CustomPromptEditorView(store: customStyleStore, editingStyle: editingStyle)
        }
        .onChange(of: showEditor) { _, showing in
            if !showing { regenerateCustomPrompts() }
        }
        .onAppear { generatePrompts() }
    }

    private var createYourOwnRow: some View {
        Button {
            guard customStyleStore.canAddMore else { return }
            editingStyle = nil
            showEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(customStyleStore.canAddMore ? .stone : .fog)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Your Own")
                        .font(Constants.Typography.heading)
                        .foregroundColor(customStyleStore.canAddMore ? .ink : .fog)
                    Text("\(customStyleStore.styles.count) of \(CustomPromptStyleStore.maxStyles) custom styles")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                Spacer()
            }
            .padding(.vertical, Constants.UI.Padding.small)
        }
        .disabled(!customStyleStore.canAddMore)
    }

    private func generatePrompts() {
        guard prompts.isEmpty else { return }
        Task {
            let context = await buildActivityContext()
            activityContext = context
            prompts = PromptGenerator.generateAll(context: context)
            regenerateCustomPrompts()
        }
    }

    private func buildActivityContext() async -> ActivityContext {
        let routeSamples = walk.routeData
        let placeNames = await geocodeWalkRoute(routeSamples)
        let routeSpeeds = routeSamples.map { $0.speed }

        let recordings = walk.voiceRecordings.compactMap { recording -> RecordingContext? in
            guard let uuid = recording.uuid,
                  let text = transcriptions[uuid] else { return nil }
            let startCoord = closestCoordinate(to: recording.startDate, in: routeSamples)
            let endCoord = closestCoordinate(to: recording.endDate, in: routeSamples)
            return RecordingContext(
                text: text,
                timestamp: recording.startDate,
                startCoordinate: startCoord,
                endCoordinate: endCoord,
                wordsPerMinute: recording.wordsPerMinute
            )
        }.sorted { $0.timestamp < $1.timestamp }

        let meditations = walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .sorted { $0.startDate < $1.startDate }
            .map { MeditationContext(startDate: $0.startDate, endDate: $0.endDate, duration: $0.duration) }

        let waypointContexts = walk.waypoints.map { wp in
            WaypointContext(
                label: wp.label, icon: wp.icon, timestamp: wp.timestamp,
                coordinate: (lat: wp.latitude, lon: wp.longitude)
            )
        }

        let celestial: CelestialSnapshot?
        if UserPreferences.celestialAwarenessEnabled.value {
            let system = ZodiacSystem(rawValue: UserPreferences.zodiacSystem.value) ?? .tropical
            celestial = CelestialCalculator.snapshot(for: walk.startDate, system: system)
        } else {
            celestial = nil
        }

        let (photoEntries, narrativeArc) = buildPhotoContext()

        return ActivityContext(
            recordings: recordings,
            meditations: meditations,
            duration: walk.activeDuration,
            distance: walk.distance,
            startDate: walk.startDate,
            placeNames: placeNames,
            routeSpeeds: routeSpeeds,
            recentWalkSnippets: recentWalkSnippets,
            intention: intention,
            waypoints: waypointContexts,
            weather: ContextFormatter.formatWeather(walk),
            lunarPhase: LunarPhase.current(date: walk.startDate),
            celestial: celestial,
            photoContexts: photoEntries,
            narrativeArc: narrativeArc
        )
    }

    private func buildPhotoContext() -> ([PhotoContextEntry], NarrativeArc?) {
        let pinnedPhotos = photoCandidates.filter(\.isPinned)
        guard !pinnedPhotos.isEmpty else { return ([], nil) }

        let isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers
        let routeSamples = walk.routeData

        var arcEntries: [PhotoNarrativeArcBuilder.Entry] = []
        var promptEntries: [PhotoContextEntry] = []

        for (i, photo) in pinnedPhotos.enumerated() {
            guard let context = PhotoContextAnalyzer.analyzeSync(localIdentifier: photo.localIdentifier) else {
                continue
            }

            let dist = distanceAtTimestamp(photo.capturedAt, in: routeSamples)
            let distStr: String
            if isMetric {
                distStr = dist < 1000 ? "\(Int(dist)) m in" : String(format: "%.1f km in", dist / 1000)
            } else {
                let miles = dist / 1609.344
                distStr = miles < 0.1 ? "\(Int(dist * 3.281)) ft in" : String(format: "%.1f mi in", miles)
            }

            let timeStr = ContextFormatter.timeFormatter.string(from: photo.capturedAt)

            arcEntries.append(PhotoNarrativeArcBuilder.Entry(
                context: context,
                capturedAt: photo.capturedAt,
                distanceIntoWalk: dist
            ))

            promptEntries.append(PhotoContextEntry(
                index: i + 1,
                distanceIntoWalk: distStr,
                time: timeStr,
                coordinate: (lat: photo.capturedLat, lon: photo.capturedLng),
                context: context
            ))
        }

        let arc = arcEntries.isEmpty ? nil : PhotoNarrativeArcBuilder.build(from: arcEntries)
        return (promptEntries, arc)
    }

    private func distanceAtTimestamp(_ target: Date, in samples: [RouteDataSampleInterface]) -> Double {
        var cumDist: Double = 0
        for i in 1..<samples.count {
            if samples[i].timestamp > target { break }
            let dlat = (samples[i].latitude - samples[i - 1].latitude) * 111320
            let dlon = (samples[i].longitude - samples[i - 1].longitude) * 111320 * cos(samples[i].latitude * .pi / 180)
            cumDist += sqrt(dlat * dlat + dlon * dlon)
        }
        return cumDist
    }

    private func geocodeWalkRoute(_ samples: [RouteDataSampleInterface]) async -> [PlaceContext] {
        guard let first = samples.first, let last = samples.last else { return [] }
        let geocoder = CLGeocoder()
        var places: [PlaceContext] = []

        if let name = await reverseGeocode(geocoder: geocoder, lat: first.latitude, lon: first.longitude, delay: false) {
            places.append(PlaceContext(name: name, coordinate: (lat: first.latitude, lon: first.longitude), role: .start))
        }

        let distance = CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        if distance > 500, let name = await reverseGeocode(geocoder: geocoder, lat: last.latitude, lon: last.longitude) {
            places.append(PlaceContext(name: name, coordinate: (lat: last.latitude, lon: last.longitude), role: .end))
        }

        return places
    }

    private func reverseGeocode(geocoder: CLGeocoder, lat: Double, lon: Double, delay: Bool = true) async -> String? {
        do {
            if delay {
                try await Task.sleep(nanoseconds: 1_100_000_000)
            }
            let placemarks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
            guard let pm = placemarks.first else { return nil }
            let parts = [pm.name, pm.locality].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        } catch {
            return nil
        }
    }

    private func regenerateCustomPrompts() {
        guard let context = activityContext else { return }
        customPrompts = customStyleStore.styles.map { customStyle in
            PromptGenerator.generateCustom(customStyle: customStyle, context: context)
        }
    }

    private func closestCoordinate(to date: Date, in samples: [RouteDataSampleInterface]) -> (lat: Double, lon: Double)? {
        guard let closest = samples.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }) else { return nil }
        return (lat: closest.latitude, lon: closest.longitude)
    }
}

struct PromptStyleRow: View {
    let prompt: GeneratedPrompt

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: prompt.icon)
                .font(.title2)
                .foregroundColor(.stone)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Text(prompt.subtitle)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.fog)
        }
        .padding(.vertical, Constants.UI.Padding.small)
    }
}
