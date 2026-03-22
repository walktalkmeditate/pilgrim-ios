import Foundation

final class CollectiveCounterService: ObservableObject {

    static let shared = CollectiveCounterService()

    @Published var stats: CollectiveStats?
    @Published var milestone: CollectiveMilestone?

    private let baseURL = "https://walk.pilgrimapp.org/api/counter"
    private let pendingKey = "collectivePendingDelta"
    private let cachedStatsKey = "collectiveCachedStats"

    private init() {
        loadCachedStats()
    }

    struct CollectiveStats: Codable {
        let totalWalks: Int
        let totalDistanceKm: Double
        let totalMeditationMin: Int
        let totalTalkMin: Int
        let lastWalkAt: String?

        enum CodingKeys: String, CodingKey {
            case totalWalks = "total_walks"
            case totalDistanceKm = "total_distance_km"
            case totalMeditationMin = "total_meditation_min"
            case totalTalkMin = "total_talk_min"
            case lastWalkAt = "last_walk_at"
        }

        var pilgrimageProgress: PilgrimageProgress {
            PilgrimageProgress.from(distanceKm: totalDistanceKm)
        }

        var meditationHours: Int {
            totalMeditationMin / 60
        }

        private static let dateFormatter = ISO8601DateFormatter()

        var walkedInLastHour: Bool {
            guard let lastWalkAt, let date = Self.dateFormatter.date(from: lastWalkAt) else { return false }
            return Date().timeIntervalSince(date) < 3600
        }
    }

    func fetch() async {
        guard let url = URL(string: baseURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CollectiveStats.self, from: data)
            await MainActor.run {
                self.stats = decoded
                self.cacheStats(data)
                self.checkMilestone(decoded.totalWalks)
            }
        } catch {
            // Stale cache is fine
        }
    }

    func recordWalk(distanceKm: Double, meditationMin: Int, talkMin: Int) {
        guard UserPreferences.contributeToCollective.value else { return }

        var pending = loadPending()
        pending.walks += 1
        pending.distanceKm += distanceKm
        pending.meditationMin += meditationMin
        pending.talkMin += talkMin

        Task.detached(priority: .background) { [self] in
            let success = await self.postCounter(pending)
            if success {
                self.clearPending()
            } else {
                self.savePending(pending)
            }
        }
    }

    private func postCounter(_ delta: PendingDelta) async -> Bool {
        guard let url = URL(string: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "walks": delta.walks,
            "distance_km": delta.distanceKm,
            "meditation_min": delta.meditationMin,
            "talk_min": delta.talkMin,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func checkMilestone(_ totalWalks: Int) {
        let lastSeen = UserPreferences.lastSeenCollectiveWalks.value
        let sacredNumbers = [108, 1_080, 2_160, 10_000, 33_333, 88_000, 108_000]

        for number in sacredNumbers {
            if totalWalks >= number && lastSeen < number {
                milestone = CollectiveMilestone.forNumber(number)
                break
            }
        }
        UserPreferences.lastSeenCollectiveWalks.value = totalWalks
    }

    private func loadCachedStats() {
        guard let data = UserDefaults.standard.data(forKey: cachedStatsKey) else { return }
        stats = try? JSONDecoder().decode(CollectiveStats.self, from: data)
    }

    private func cacheStats(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cachedStatsKey)
    }

    struct PendingDelta: Codable {
        var walks: Int = 0
        var distanceKm: Double = 0
        var meditationMin: Int = 0
        var talkMin: Int = 0
    }

    private func loadPending() -> PendingDelta {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return PendingDelta() }
        return (try? JSONDecoder().decode(PendingDelta.self, from: data)) ?? PendingDelta()
    }

    private func savePending(_ delta: PendingDelta) {
        let data = try? JSONEncoder().encode(delta)
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    private func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }
}
