import SwiftUI
import CoreLocation

struct PromptListView: View {

    let walk: WalkInterface
    let transcriptions: [UUID: String]
    let recentWalkSnippets: [PromptGenerator.WalkSnippet]
    let intention: String?
    @State private var selectedPrompt: GeneratedPrompt?
    @State private var prompts: [GeneratedPrompt] = []
    @StateObject private var customStyleStore = CustomPromptStyleStore()
    @State private var showEditor = false
    @State private var editingStyle: CustomPromptStyle?
    @State private var geocodedPlaces: [PromptGenerator.PlaceContext] = []
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
        .onChange(of: showEditor) { showing in
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
            let routeSamples = walk.routeData
            let placeNames = await geocodeWalkRoute(routeSamples)
            geocodedPlaces = placeNames
            let routeSpeeds = routeSamples.map { $0.speed }

            let recordings = walk.voiceRecordings.compactMap { recording -> PromptGenerator.RecordingContext? in
                guard let uuid = recording.uuid,
                      let text = transcriptions[uuid] else { return nil }
                let startCoord = closestCoordinate(to: recording.startDate, in: routeSamples)
                let endCoord = closestCoordinate(to: recording.endDate, in: routeSamples)
                return PromptGenerator.RecordingContext(
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
                .map { PromptGenerator.MeditationContext(startDate: $0.startDate, endDate: $0.endDate, duration: $0.duration) }

            prompts = PromptGenerator.generateAll(
                recordings: recordings,
                meditations: meditations,
                duration: walk.activeDuration,
                distance: walk.distance,
                startDate: walk.startDate,
                placeNames: placeNames,
                routeSpeeds: routeSpeeds,
                recentWalkSnippets: recentWalkSnippets,
                intention: intention
            )
            regenerateCustomPrompts()
        }
    }

    private func geocodeWalkRoute(_ samples: [RouteDataSampleInterface]) async -> [PromptGenerator.PlaceContext] {
        guard let first = samples.first, let last = samples.last else { return [] }
        let geocoder = CLGeocoder()
        var places: [PromptGenerator.PlaceContext] = []

        if let name = await reverseGeocode(geocoder: geocoder, lat: first.latitude, lon: first.longitude, delay: false) {
            places.append(PromptGenerator.PlaceContext(name: name, coordinate: (lat: first.latitude, lon: first.longitude), role: .start))
        }

        let distance = CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        if distance > 500, let name = await reverseGeocode(geocoder: geocoder, lat: last.latitude, lon: last.longitude) {
            places.append(PromptGenerator.PlaceContext(name: name, coordinate: (lat: last.latitude, lon: last.longitude), role: .end))
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
        let routeSamples = walk.routeData
        let routeSpeeds = routeSamples.map { $0.speed }
        let recordings = walk.voiceRecordings.compactMap { recording -> PromptGenerator.RecordingContext? in
            guard let uuid = recording.uuid,
                  let text = transcriptions[uuid] else { return nil }
            return PromptGenerator.RecordingContext(
                text: text,
                timestamp: recording.startDate,
                startCoordinate: closestCoordinate(to: recording.startDate, in: routeSamples),
                endCoordinate: closestCoordinate(to: recording.endDate, in: routeSamples),
                wordsPerMinute: recording.wordsPerMinute
            )
        }.sorted { $0.timestamp < $1.timestamp }
        let meditations = walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .sorted { $0.startDate < $1.startDate }
            .map { PromptGenerator.MeditationContext(startDate: $0.startDate, endDate: $0.endDate, duration: $0.duration) }

        customPrompts = customStyleStore.styles.map { customStyle in
            PromptGenerator.generateCustom(
                customStyle: customStyle,
                recordings: recordings,
                meditations: meditations,
                duration: walk.activeDuration,
                distance: walk.distance,
                startDate: walk.startDate,
                placeNames: geocodedPlaces,
                routeSpeeds: routeSpeeds,
                recentWalkSnippets: recentWalkSnippets,
                intention: intention
            )
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
