import Foundation

final class CollectiveCounterService: ObservableObject {

    static let shared = CollectiveCounterService()

    @Published var stats: CollectiveStats?
    @Published var milestone: CollectiveMilestone?

    private let baseURL = "https://walk.pilgrimapp.org/api/counter"
    private let pendingKey = "collectivePendingDelta"
    private let cachedStatsKey = "collectiveCachedStats"

    /// How long a successful fetch suppresses subsequent fetches.
    /// Settings is the only surface that calls `fetch()` on view
    /// appearance, so without a TTL every settings open hits the
    /// network. 216s is short enough that the counter still feels
    /// alive between visits and long enough to absorb rapid
    /// open/close. To bypass it (e.g. after a walk-end POST), set
    /// `lastFetchedAt = nil` and call `fetch()` again — there is no
    /// `force` flag, deliberately, so view code can't accidentally
    /// defeat the gate.
    private static let fetchTTL: TimeInterval = 216

    private var lastFetchedAt: Date?

    private init() {
        loadCachedStats()
    }

    struct CollectiveStats: Codable {
        let totalWalks: Int
        let totalDistanceKm: Double
        let totalMeditationMin: Int
        let totalTalkMin: Int
        let lastWalkAt: String?
        let streakDays: Int?
        let streakDate: String?

        enum CodingKeys: String, CodingKey {
            case totalWalks = "total_walks"
            case totalDistanceKm = "total_distance_km"
            case totalMeditationMin = "total_meditation_min"
            case totalTalkMin = "total_talk_min"
            case lastWalkAt = "last_walk_at"
            case streakDays = "streak_days"
            case streakDate = "streak_date"
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
        if let last = lastFetchedAt, Date().timeIntervalSince(last) < Self.fetchTTL {
            return
        }
        guard let url = URL(string: baseURL) else { return }
        // Bypass URLCache. The worker sends Cache-Control: max-age=10800
        // (3 hours), so the default policy would serve cached responses
        // for hours — including a fetch right after a walk POST, which
        // is exactly the moment we want fresh data. The 216s in-memory
        // TTL above is the only rate limiter we want.
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(CollectiveStats.self, from: data)
            await MainActor.run {
                self.stats = decoded
                self.lastFetchedAt = Date()
                self.cacheStats(data)
                self.checkMilestone(decoded.totalWalks)
            }
        } catch {
            print("[CollectiveCounter] fetch failed: \(error.localizedDescription)")
        }
    }

    func recordWalk(distanceKm: Double, meditationMin: Int, talkMin: Int) {
        guard UserPreferences.contributeToCollective.value else { return }

        DispatchQueue.main.async {
            var pending = self.loadPending()
            pending.walks += 1
            pending.distanceKm += distanceKm
            pending.meditationMin += meditationMin
            pending.talkMin += talkMin
            self.savePending(pending)

            let snapshot = pending
            Task {
                let success = await self.postCounter(snapshot)
                if success {
                    await MainActor.run {
                        var current = self.loadPending()
                        current.walks -= snapshot.walks
                        current.distanceKm -= snapshot.distanceKm
                        current.meditationMin -= snapshot.meditationMin
                        current.talkMin -= snapshot.talkMin
                        if current.walks <= 0 {
                            self.clearPending()
                        } else {
                            self.savePending(current)
                        }
                        // Invalidate the TTL gate BEFORE attempting
                        // the refetch. If the refetch fails (iOS
                        // suspended the task because the user
                        // pocketed their phone, network died, etc.),
                        // the next call to fetch() — typically the
                        // next Settings open — naturally hits the
                        // network instead of being silently locked
                        // into the pre-walk window for up to ~3.6
                        // minutes. The refetch below is now a
                        // best-effort optimization, not a
                        // correctness requirement.
                        self.lastFetchedAt = nil
                    }
                    await self.fetch()
                }
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
                UserPreferences.lastSeenCollectiveWalks.value = number
                break
            }
        }
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
