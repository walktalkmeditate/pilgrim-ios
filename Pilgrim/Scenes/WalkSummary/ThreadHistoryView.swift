import SwiftUI
import CoreStore
import CoreLocation

/// Best-effort reverse geocoding of each walk's starting point — resolved
/// once per walk, capped per screen, and strictly serialized: CLGeocoder
/// fails a pending request when a new one is submitted, so concurrent
/// per-row requests would silently lose most place names. One FIFO Task
/// awaits each lookup before starting the next; a missing place simply
/// doesn't render. The Task handle is cancelled when the view disappears.
@MainActor
final class ThreadPlaceResolver: ObservableObject {

    @Published private(set) var places: [UUID: String] = [:]
    private let geocoder = CLGeocoder()
    private var resolveTask: Task<Void, Never>?
    private static let maxResolutions = 12

    /// Called exactly once, from load(), with the entries' distinct walk
    /// UUIDs in display order — never per row.
    func resolveAll(walkUUIDs: [UUID]) {
        guard resolveTask == nil else { return }
        let pending = walkUUIDs.prefix(Self.maxResolutions)
        resolveTask = Task {
            for walkUUID in pending {
                guard !Task.isCancelled else { return }
                guard let walk = try? DataManager.dataStack.fetchOne(
                    From<Walk>().where(\._uuid == walkUUID)
                ), let first = walk.routeData.first else { continue }
                let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
                guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
                      let name = placemark.locality ?? placemark.name else { continue }
                places[walkUUID] = name
            }
        }
    }

    func cancel() {
        resolveTask?.cancel()
        resolveTask = nil
    }
}

/// A thread's full history, newest first — date, place, and the walker's
/// own words around each mention. The oldest entry is labeled "where it
/// began" and offers the origin walk's map when a route fix exists.
struct ThreadHistoryView: View {

    let displayTerm: String
    let cohortLemmas: [String]

    @State private var entries: [ThreadHistoryEntry] = []
    @State private var origin: OriginMapData?
    @State private var selectedWalk: Walk?
    @State private var presentedOriginMap: OriginMapData?
    @State private var showReleaseConfirm = false
    @StateObject private var placeResolver = ThreadPlaceResolver()
    @Environment(\.dismiss) private var dismiss

    struct OriginMapData: Identifiable {
        let id = UUID()
        let walk: Walk
        let coordinate: CLLocationCoordinate2D
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                termHeader
                ForEach(entries, id: \.recordingUUID) { entry in
                    entryRow(entry)
                }
            }
            .padding(Constants.UI.Padding.normal)
        }
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayTerm)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .sheet(item: $selectedWalk) { walk in
            // showsThreadsCard: false is the Task 3 recursion cut — a
            // tap-through summary must not offer another threads card, or
            // summary → thread → summary stacks Mapbox-bearing views
            // without bound.
            WalkSummaryView(walk: walk, showsThreadsCard: false)
        }
        .sheet(item: $presentedOriginMap) { data in
            ThreadOriginMapView(displayTerm: displayTerm, data: data)
        }
        .alert(
            ReleasedThreadsCopy.releaseTitle(displayTerm),
            isPresented: $showReleaseConfirm
        ) {
            Button(ReleasedThreadsCopy.releaseConfirm) {
                ReleasedThreadsStore.shared.release(displayTerm: displayTerm, lemmas: cohortLemmas)
                dismiss()
            }
            Button(ReleasedThreadsCopy.releaseCancel, role: .cancel) {}
        } message: {
            Text(ReleasedThreadsCopy.releaseMessage)
        }
        .task { await load() }
        .onDisappear { placeResolver.cancel() }
    }

    private var termHeader: some View {
        Text(displayTerm)
            .font(Constants.Typography.displayMedium)
            .foregroundColor(.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .onLongPressGesture { showReleaseConfirm = true }
            .accessibilityAction(named: ReleasedThreadsCopy.voiceOverActionName) {
                showReleaseConfirm = true
            }
    }

    private func entryRow(_ entry: ThreadHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            Button {
                selectedWalk = try? DataManager.dataStack.fetchOne(
                    From<Walk>().where(\._uuid == entry.walkUUID)
                )
            } label: {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
                    HStack(spacing: Constants.UI.Padding.xs) {
                        Text(Self.dateFormatter.string(from: entry.date))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                        if let place = placeResolver.places[entry.walkUUID] {
                            Text("· \(place)")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                    if let excerpt = entry.excerpt {
                        Text(excerpt)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap to open this walk's summary")

            if entry.isOrigin {
                originFooter
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private var originFooter: some View {
        HStack(spacing: Constants.UI.Padding.xs) {
            Image(systemName: "leaf")
                .font(.caption)
                .foregroundColor(.moss)
            Text("where it began")
                .font(Constants.Typography.caption)
                .foregroundColor(.moss)
            Spacer()
            if origin != nil {
                Button {
                    guard let fresh = resolveOrigin() else {
                        origin = nil
                        return
                    }
                    presentedOriginMap = fresh
                } label: {
                    Text("open the map")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard UserPreferences.threadsAfterWalks.value else { return }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let transcripts = Dictionary(
            uniqueKeysWithValues: DataManager.transcribedRecordingsSnapshot()
                .map { ($0.uuid, $0.transcript) }
        )
        let released = ReleasedThreadsStore.shared.releasedLemmas
        let backfillComplete = ThreadsBackfill.isComplete
        let lemmas = Set(cohortLemmas)

        entries = await Task.detached(priority: .userInitiated) { () -> [ThreadHistoryEntry] in
            let contexts = TranscriptContextStore.shared.loadAll()
            let contextsByRecording = Dictionary(
                uniqueKeysWithValues: contexts.map { ($0.recordingUUID, $0) }
            )
            let threads = ThreadStore.build(contexts: contexts, walks: walkIndex, released: released)
            return ThreadHistoryModelBuilder.entries(
                cohort: threads.filter { lemmas.contains($0.lemma) },
                contextsByRecording: contextsByRecording,
                transcriptsByRecording: transcripts,
                backfillComplete: backfillComplete
            )
        }.value
        origin = resolveOrigin()
        var seenWalks: Set<UUID> = []
        placeResolver.resolveAll(
            walkUUIDs: entries.map(\.walkUUID).filter { seenWalks.insert($0).inserted }
        )
    }

    /// Called at load (to decide whether the footer's map button renders)
    /// and again at tap (to fetch a fresh walk + coordinate right before
    /// presenting) — never persisted, so a walk deleted in between is never
    /// shown stale: the tap either presents fresh data or, finding nothing,
    /// hides the action on the spot. A deleted origin walk or a fix gap
    /// simply means the record's earliest surviving appearance becomes
    /// "where it began" on the next open (spec: deletion is deliberate
    /// record-editing).
    @MainActor
    private func resolveOrigin() -> OriginMapData? {
        guard let oldest = entries.last, oldest.isOrigin,
              let walk = try? DataManager.dataStack.fetchOne(
                From<Walk>().where(\._uuid == oldest.walkUUID)
              ),
              let recording = walk.voiceRecordings.first(where: { $0.uuid == oldest.recordingUUID }),
              let coordinate = ThreadOriginResolver.coordinate(
                recordingStart: recording.startDate,
                samples: walk.routeData.map { ($0.timestamp, $0.latitude, $0.longitude) }
              ) else { return nil }
        return OriginMapData(walk: walk, coordinate: coordinate)
    }
}

/// The origin walk's map — the existing historical summary map, static and
/// read-only, no live-walk controls — centered on where the thread first
/// found words.
struct ThreadOriginMapView: View {

    let displayTerm: String
    let data: ThreadHistoryView.OriginMapData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PilgrimMapView(
                isInteractive: false,
                showsUserLocation: false,
                routeSegments: WalkSummaryView.computeSegments(for: data.walk),
                pinAnnotations: [PilgrimAnnotation(
                    coordinate: data.coordinate,
                    kind: .voiceRecording(label: "where it began")
                )],
                initialCamera: MapCameraSeed.Seed(center: data.coordinate, zoom: 15)
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Where '\(displayTerm)' began")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.stone)
                }
            }
        }
    }
}
