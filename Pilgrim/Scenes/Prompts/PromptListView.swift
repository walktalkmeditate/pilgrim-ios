import SwiftUI

struct PromptListView: View {

    let walk: WalkInterface
    let transcriptions: [UUID: String]
    @State private var selectedPrompt: GeneratedPrompt?
    @State private var prompts: [GeneratedPrompt] = []

    var body: some View {
        List {
            ForEach(prompts) { prompt in
                Button {
                    selectedPrompt = prompt
                } label: {
                    PromptStyleRow(prompt: prompt)
                }
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
        .onAppear { generatePrompts() }
    }

    private func generatePrompts() {
        guard prompts.isEmpty else { return }
        let routeSamples = walk.routeData
        let recordings = walk.voiceRecordings.compactMap { recording -> PromptGenerator.RecordingContext? in
            guard let uuid = recording.uuid,
                  let text = transcriptions[uuid] else { return nil }
            let startCoord = closestCoordinate(to: recording.startDate, in: routeSamples)
            let endCoord = closestCoordinate(to: recording.endDate, in: routeSamples)
            return PromptGenerator.RecordingContext(
                text: text,
                timestamp: recording.startDate,
                startCoordinate: startCoord,
                endCoordinate: endCoord
            )
        }.sorted { $0.timestamp < $1.timestamp }

        let meditations = walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .sorted { $0.startDate < $1.startDate }
            .map { PromptGenerator.MeditationContext(
                startDate: $0.startDate,
                endDate: $0.endDate,
                duration: $0.duration
            )}

        prompts = PromptGenerator.generateAll(
            recordings: recordings,
            meditations: meditations,
            duration: walk.activeDuration,
            distance: walk.distance,
            startDate: walk.startDate
        )
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
