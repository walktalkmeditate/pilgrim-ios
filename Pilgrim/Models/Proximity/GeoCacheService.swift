import Foundation
import CoreLocation
import Combine

final class GeoCacheService: ObservableObject {

    static let shared = GeoCacheService()

    @Published var cachedWhispers: [CachedWhisper] = []
    @Published var cachedCairns: [CachedCairn] = []

    private let cacheRadiusMeters: Double = 50_000
    private let refetchThresholdMeters: Double = 10_000
    private var lastFetchCenter: CLLocationCoordinate2D?
    private var whispersETag: String?
    private var cairnsETag: String?

    private let baseURL = "https://walk.pilgrimapp.org/api"
    private let cachedWhispersKey = "geoCachedWhispers"
    private let cachedCairnsKey = "geoCachedCairns"
    private let pendingPlacementsKey = "pendingPlacements"

    private init() {
        loadCachedWhispers()
        loadCachedCairns()
    }

    func invalidateLastFetch() {
        lastFetchCenter = nil
        whispersETag = nil
        cairnsETag = nil
    }

    func fetchIfNeeded(near coordinate: CLLocationCoordinate2D) async {
        if let center = lastFetchCenter {
            let distance = CLLocation(latitude: center.latitude, longitude: center.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance > refetchThresholdMeters else { return }
        }

        lastFetchCenter = coordinate
        async let w: () = fetchWhispers(lat: coordinate.latitude, lon: coordinate.longitude)
        async let c: () = fetchCairns(lat: coordinate.latitude, lon: coordinate.longitude)
        _ = await (w, c)

        await syncPendingPlacements()
    }

    func proximityTargets() -> Set<ProximityTarget> {
        var targets = Set<ProximityTarget>()

        for whisper in cachedWhispers {
            targets.insert(ProximityTarget(
                id: "whisper-\(whisper.id)",
                coordinate: CLLocationCoordinate2D(latitude: whisper.latitude, longitude: whisper.longitude),
                radius: ProximityDetectionService.whisperRadius,
                type: .whisper
            ))
        }

        for cairn in cachedCairns {
            targets.insert(ProximityTarget(
                id: "cairn-\(cairn.id)",
                coordinate: CLLocationCoordinate2D(latitude: cairn.latitude, longitude: cairn.longitude),
                radius: ProximityDetectionService.cairnRadius,
                type: .cairn
            ))
        }

        return targets
    }

    // MARK: - Whispers

    private func fetchWhispers(lat: Double, lon: Double) async {
        guard let url = URL(string: "\(baseURL)/whispers?lat=\(lat)&lon=\(lon)&radius=\(Int(cacheRadiusMeters))") else { return }
        var request = URLRequest(url: url)
        if let etag = whispersETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 { return }
            guard (200...299).contains(http.statusCode) else { return }

            whispersETag = http.value(forHTTPHeaderField: "ETag")
            let decoded = try JSONDecoder().decode([CachedWhisper].self, from: data)
            await MainActor.run {
                self.cachedWhispers = decoded
                self.persistWhispers(data)
            }
        } catch {
            print("[GeoCacheService] whispers fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cairns

    private func fetchCairns(lat: Double, lon: Double) async {
        guard let url = URL(string: "\(baseURL)/cairns?lat=\(lat)&lon=\(lon)&radius=\(Int(cacheRadiusMeters))") else { return }
        var request = URLRequest(url: url)
        if let etag = cairnsETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 304 { return }
            guard (200...299).contains(http.statusCode) else { return }

            cairnsETag = http.value(forHTTPHeaderField: "ETag")
            let decoded = try JSONDecoder().decode([CachedCairn].self, from: data)
            await MainActor.run {
                self.cachedCairns = decoded
                self.persistCairns(data)
            }
        } catch {
            print("[GeoCacheService] cairns fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Offline Sync

    func queuePlacement(_ placement: PendingPlacement) {
        var pending = loadPendingPlacements()
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        pending.removeAll { $0.timestamp < sevenDaysAgo }
        guard pending.count < 50 else { return }
        pending.append(placement)
        savePendingPlacements(pending)
    }

    private func syncPendingPlacements() async {
        var pending = loadPendingPlacements()
        guard !pending.isEmpty else { return }

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        pending.removeAll { $0.timestamp < sevenDaysAgo }

        var remaining: [PendingPlacement] = []
        for placement in pending {
            let success: Bool
            switch placement.type {
            case .whisper:
                success = await postPendingWhisper(placement)
            case .stone:
                success = await postPendingStone(placement)
            }
            if !success {
                remaining.append(placement)
            }
        }

        if remaining.isEmpty {
            clearPendingPlacements()
        } else {
            savePendingPlacements(remaining)
        }
    }

    private func postPendingWhisper(_ placement: PendingPlacement) async -> Bool {
        guard let url = URL(string: "\(baseURL)/whispers") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.httpBody = injectCoordinates(placement)
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func postPendingStone(_ placement: PendingPlacement) async -> Bool {
        guard let url = URL(string: "\(baseURL)/cairns") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.httpBody = injectCoordinates(placement)
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Persistence

    private func loadCachedWhispers() {
        guard let data = UserDefaults.standard.data(forKey: cachedWhispersKey) else { return }
        cachedWhispers = (try? JSONDecoder().decode([CachedWhisper].self, from: data)) ?? []
    }

    private func persistWhispers(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cachedWhispersKey)
    }

    func persistCurrentWhispers() {
        guard let data = try? JSONEncoder().encode(cachedWhispers) else { return }
        UserDefaults.standard.set(data, forKey: cachedWhispersKey)
    }

    private func loadCachedCairns() {
        guard let data = UserDefaults.standard.data(forKey: cachedCairnsKey) else { return }
        cachedCairns = (try? JSONDecoder().decode([CachedCairn].self, from: data)) ?? []
    }

    private func persistCairns(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cachedCairnsKey)
    }

    func persistCurrentCairns() {
        guard let data = try? JSONEncoder().encode(cachedCairns) else { return }
        UserDefaults.standard.set(data, forKey: cachedCairnsKey)
    }

    private func loadPendingPlacements() -> [PendingPlacement] {
        guard let data = UserDefaults.standard.data(forKey: pendingPlacementsKey) else { return [] }
        return (try? JSONDecoder().decode([PendingPlacement].self, from: data)) ?? []
    }

    private func savePendingPlacements(_ placements: [PendingPlacement]) {
        let data = try? JSONEncoder().encode(placements)
        UserDefaults.standard.set(data, forKey: pendingPlacementsKey)
    }

    private func clearPendingPlacements() {
        UserDefaults.standard.removeObject(forKey: pendingPlacementsKey)
    }

    private func injectCoordinates(_ placement: PendingPlacement) -> Data? {
        var dict = (try? JSONSerialization.jsonObject(with: placement.payload) as? [String: Any]) ?? [:]
        dict["latitude"] = placement.latitude
        dict["longitude"] = placement.longitude
        return try? JSONSerialization.data(withJSONObject: dict)
    }
}
